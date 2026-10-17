-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-193: obtener insignia
--
-- Una insignia se gana al llegar a una cantidad de XP acumulada.
-- La otorga la base, igual que la XP (0009): el cliente solo
-- lee el catálogo y las suyas, y no puede escribir en ninguna de
-- las dos tablas. Una insignia vale lo que vale la XP que la dio:
-- si alguien consigue XP que no le corresponde, también gana sus
-- insignias. Por eso cada una guarda con cuánta XP se obtuvo.
--
-- Decisiones:
--   - Se otorgan en un trigger sobre `experiencia_ganada`: cada
--     vez que entra XP se compara la acumulada con los umbrales.
--     Cubre la XP de actividades y de retos por igual.
--   - Una insignia obtenida se conserva aunque la XP baje (por
--     ejemplo, si el usuario borra un entrenamiento): es el
--     registro de un logro, no un reflejo de la XP actual.
--   - El catálogo lo carga esta migración. No hay pantalla de
--     administración; cambiarlo es otra migración.
--   - Los usuarios que ya tienen XP reciben aquí las insignias
--     que les corresponden (sección 5), sin esperar su próxima
--     actividad.
--
-- Corre esto DESPUÉS de 0009_experiencia.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Catálogo de insignias
-- -------------------------------------------------------------
create table insignias (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  descripcion     text not null,
  -- Clave del dibujo en la app (`SeccionInsignias`). Si llega una
  -- que la app no conoce, dibuja un icono genérico.
  icono           text not null,
  -- XP acumulada con la que se gana.
  xp_requerida    integer not null,
  fecha_creacion  timestamptz not null default now()
);

alter table insignias
  add constraint insignias_xp_requerida_positiva
    check (xp_requerida > 0),
  add constraint insignias_nombre_no_vacio
    check (length(btrim(nombre)) > 0),
  add constraint insignias_icono_no_vacio
    check (length(btrim(icono)) > 0),
  add constraint insignias_nombre_unico
    unique (nombre);

-- -------------------------------------------------------------
-- 2. Insignias de cada usuario
-- -------------------------------------------------------------
create table insignias_usuario (
  id               uuid primary key default gen_random_uuid(),
  usuario_id       uuid not null references auth.users(id) on delete cascade,
  insignia_id      uuid not null references insignias(id) on delete cascade,
  fecha_obtencion  timestamptz not null default now(),
  -- XP acumulada cuando se otorgó. La insignia se conserva aunque
  -- la XP baje; esto deja rastro para auditar de dónde salió.
  xp_al_obtener    integer not null,
  -- Criterio 5: una insignia se tiene una sola vez. Es la última
  -- palabra aunque dos cierres lleguen al mismo tiempo. El índice
  -- que crea también sirve para filtrar por usuario.
  constraint insignias_usuario_una_vez
    unique (usuario_id, insignia_id)
);

-- -------------------------------------------------------------
-- 3. RLS
--
-- Solo lectura. Sin policies de insert, update ni delete: el
-- catálogo lo escribe esta migración y las insignias de cada
-- usuario, el trigger, que es security definer.
-- -------------------------------------------------------------
alter table insignias enable row level security;

create policy "las insignias las lee cualquier usuario autenticado"
  on insignias
  for select
  using (auth.role() = 'authenticated');

alter table insignias_usuario enable row level security;

create policy "usuario ve sus propias insignias"
  on insignias_usuario
  for select
  using (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 4. El trigger: insignias al ganar XP
--
-- Otorga de una vez todas las insignias cuyo umbral ya alcanzó
-- la XP acumulada y que el usuario no tenga (criterios 1 a 4).
-- `on conflict do nothing` evita duplicarlas (criterio 5).
--
-- Tolerante a fallos, y por una razón concreta: la XP la inserta
-- `otorgar_experiencia` (0009) dentro de su propio bloque
-- `exception`. Si este trigger lanzara un error, ese bloque
-- desharía también la XP del entrenamiento. Aquí se deshacen
-- solo las insignias, queda un warning en los logs de Postgres
-- y se vuelven a evaluar con la siguiente XP que entre.
--
-- El bloqueo por usuario es el mismo de 0009 (en la misma
-- transacción ya lo tiene, y no estorba): dos cierres
-- simultáneos no leen la misma suma a la vez.
-- -------------------------------------------------------------
create function public.otorgar_insignias()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_total integer;
begin
  begin
    perform pg_advisory_xact_lock(hashtext(new.usuario_id::text));

    -- `after insert`: la suma ya incluye la fila nueva.
    select coalesce(sum(cantidad), 0)::integer into v_total
    from experiencia_ganada
    where usuario_id = new.usuario_id;

    insert into insignias_usuario (usuario_id, insignia_id, xp_al_obtener)
    select new.usuario_id, i.id, v_total
    from insignias i
    where i.xp_requerida <= v_total
    on conflict (usuario_id, insignia_id) do nothing;
  exception when others then
    raise warning 'No se pudieron otorgar insignias al usuario %: % (%)',
      new.usuario_id, sqlerrm, sqlstate;
  end;

  return new;
end;
$$;

-- Solo la usa el trigger. Nadie la llama directo.
revoke execute on function public.otorgar_insignias()
  from public, anon, authenticated;

-- Una fila con 0 XP no cambia la acumulada: no hay nada nuevo que
-- ganar.
create trigger otorgar_insignias_al_ganar_experiencia
  after insert on experiencia_ganada
  for each row
  when (new.cantidad > 0)
  execute function public.otorgar_insignias();

-- -------------------------------------------------------------
-- 5. Catálogo inicial
--
-- Umbrales pensados con las reglas de 0009: una actividad da
-- 5 XP por km, así que cada insignia equivale a una distancia
-- reconocible. La XP de los retos también cuenta, así que en la
-- práctica se llega antes.
-- -------------------------------------------------------------
insert into insignias (nombre, descripcion, icono, xp_requerida) values
  ('Primera huella',     'Tu primer kilómetro con TRAZA.',                        'huella',     5),
  ('Calentando motores', 'Un 5K en tus piernas.',                                 'fuego',     25),
  ('Diez mil',           'La distancia reina de las carreras populares.',         'diez',      50),
  ('Media maratón',      'La mitad del camino del mito: 21,1 km.',                'media',    105),
  ('Maratonista',        'Lo que corrió Filípides, ahora en tu cuenta.',          'maraton',  211),
  ('Dueño de la calle',  'Tres cifras de kilómetros recorridos.',                 'calle',    500),
  ('Eterna primavera',   'Medellín de punta a punta, muchas veces.',              'primavera',1000),
  ('Cruzando Colombia',  'Casi lo que hay de Medellín a Cartagena.',              'colombia', 2500),
  ('Leyenda TRAZA',      'Mil kilómetros de constancia.',                         'leyenda',  5000);

-- Quien ya tenía XP antes de esta migración recibe lo suyo ahora.
insert into insignias_usuario (usuario_id, insignia_id, xp_al_obtener)
select acumulada.usuario_id, i.id, acumulada.total
from (
  select usuario_id, sum(cantidad) as total
  from experiencia_ganada
  group by usuario_id
) acumulada
join insignias i on i.xp_requerida <= acumulada.total
on conflict (usuario_id, insignia_id) do nothing;


-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea dos usuarios de prueba y revisa los criterios 1 a 5, el
-- camino real (finalizar un entrenamiento), la tolerancia a
-- fallos, que las insignias se conservan y el RLS. Al final lanza
-- un error A PROPÓSITO para que todo se deshaga: no deja nada en
-- la base. El resultado es el mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
--
-- Lo esperado se calcula con el catálogo, así el script sigue
-- sirviendo si otra migración lo cambia.
-- =============================================================
/*
do $$
declare
  v_usuario   uuid := gen_random_uuid();
  v_otro      uuid := gen_random_uuid();
  v_tipo      uuid := (select id from tipos_actividad limit 1);
  -- La XP que se registra directo va a un día pasado, para no
  -- gastar el tope diario del paso que finaliza de verdad.
  v_dia       date := current_date - 10;
  v_catalogo  integer := (select count(*) from insignias);
  v_pasos     integer[] := array[4, 1, 25, 200, 10];
  v_criterios text[] := array[
    'criterio 4 (4 XP: no alcanza)',
    'criterio 1 (5 XP: justo el umbral)',
    'criterio 2 (30 XP: supera un umbral)',
    'criterio 3 (230 XP: varios umbrales en un solo registro)',
    'criterio 5 (240 XP: sin duplicar)'
  ];
  v_entreno   uuid;
  v_total     integer := 0;
  v_antes     integer;
  v_tiene     integer;
  v_esperadas integer;
  v_siguiente integer;
  v_n         integer;
begin
  insert into auth.users (id, email) values
    (v_usuario, 'prueba-insignias-' || v_usuario || '@traza.test'),
    (v_otro,    'prueba-insignias-' || v_otro    || '@traza.test');

  -- Criterios 1 a 5. Cada paso registra XP como lo hace 0009 (un
  -- entrenamiento con su fila de actividad) y exige tener
  -- exactamente las insignias cuyo umbral ya alcanzó.
  for i in 1 .. array_length(v_pasos, 1) loop
    select count(*) into v_antes from insignias_usuario where usuario_id = v_usuario;

    insert into entrenamientos (usuario_id, tipo_actividad_id)
      values (v_usuario, v_tipo) returning id into v_entreno;
    insert into experiencia_ganada
      (usuario_id, entrenamiento_id, origen, cantidad, metros_contados, ajuste, dia)
      values (v_usuario, v_entreno, 'actividad', v_pasos[i], v_pasos[i] * 200, 'ninguno', v_dia);
    v_total := v_total + v_pasos[i];

    select count(*) into v_tiene from insignias_usuario where usuario_id = v_usuario;
    select count(*) into v_esperadas from insignias where xp_requerida <= v_total;
    if v_tiene <> v_esperadas then
      raise exception 'FALLÓ %: tiene % insignias, esperaba %', v_criterios[i], v_tiene, v_esperadas;
    end if;

    select count(*) into v_n
    from insignias_usuario iu join insignias ins on ins.id = iu.insignia_id
    where iu.usuario_id = v_usuario and ins.xp_requerida > v_total;
    if v_n <> 0 then
      raise exception 'FALLÓ %: tiene % insignias que no alcanza', v_criterios[i], v_n;
    end if;

    -- Que el catálogo de verdad ponga a prueba estos dos casos.
    if i = 2 and not exists (select 1 from insignias where xp_requerida = v_total) then
      raise exception 'FALLÓ %: ninguna insignia pide exactamente % XP, el caso no se probó', v_criterios[i], v_total;
    end if;
    if i = 3 and (v_tiene - v_antes < 1
                  or exists (select 1 from insignias where xp_requerida = v_total)) then
      raise exception 'FALLÓ %: el paso no superó ningún umbral, el caso no se probó', v_criterios[i];
    end if;
    if i = 4 and v_tiene - v_antes < 2 then
      raise exception 'FALLÓ %: ese registro otorgó %, esperaba varias', v_criterios[i], v_tiene - v_antes;
    end if;
  end loop;

  -- Criterio 5, directo: ninguna insignia repetida.
  select count(*) into v_n from (
    select 1 from insignias_usuario where usuario_id = v_usuario
    group by insignia_id having count(*) > 1
  ) repetidas;
  if v_n <> 0 then
    raise exception 'FALLÓ criterio 5: % insignias están repetidas', v_n;
  end if;

  -- Cada insignia guarda la XP con que se obtuvo, y alcanzaba.
  select count(*) into v_n
  from insignias_usuario iu join insignias ins on ins.id = iu.insignia_id
  where iu.usuario_id = v_usuario and iu.xp_al_obtener < ins.xp_requerida;
  if v_n <> 0 then
    raise exception 'FALLÓ rastro: % insignias guardan menos XP de la que piden', v_n;
  end if;

  -- Tolerancia, por el camino real: si otorgar insignias falla, la
  -- XP del entrenamiento se queda (el bloque `exception` de 0009 no
  -- la deshace). Se sube la XP hasta 5 menos del siguiente umbral,
  -- se rompe la tabla a propósito (`not valid`: no revisa las filas
  -- que ya tiene) y se finaliza 1 km (5 XP), que cruza el umbral.
  select min(xp_requerida) into v_siguiente from insignias where xp_requerida > v_total + 5;
  if v_siguiente is null then
    raise exception 'FALLÓ tolerancia: ninguna insignia pide más de % XP, el caso no se probó', v_total + 5;
  end if;

  insert into entrenamientos (usuario_id, tipo_actividad_id)
    values (v_usuario, v_tipo) returning id into v_entreno;
  insert into experiencia_ganada
    (usuario_id, entrenamiento_id, origen, cantidad, metros_contados, ajuste, dia)
    values (v_usuario, v_entreno, 'actividad', v_siguiente - 5 - v_total,
            (v_siguiente - 5 - v_total) * 200, 'ninguno', v_dia);
  v_total := v_siguiente - 5;

  alter table insignias_usuario
    add constraint verificacion_romper check (false) not valid;
  select count(*) into v_antes from insignias_usuario where usuario_id = v_usuario;

  insert into entrenamientos (usuario_id, tipo_actividad_id)
    values (v_usuario, v_tipo) returning id into v_entreno;
  update entrenamientos
    set estado = 'finalizado', fecha_fin = now(),
        duracion_segundos = 600, distancia_total_m = 1000
    where id = v_entreno;
  v_total := v_total + 5;

  select coalesce(sum(cantidad), 0) into v_n from experiencia_ganada where usuario_id = v_usuario;
  if v_n <> v_total then
    raise exception 'FALLÓ tolerancia: el fallo de las insignias deshizo la XP (hay %, esperaba %)', v_n, v_total;
  end if;
  select count(*) into v_tiene from insignias_usuario where usuario_id = v_usuario;
  if v_tiene <> v_antes then
    raise exception 'FALLÓ tolerancia: con la tabla rota se otorgaron % insignias', v_tiene - v_antes;
  end if;

  alter table insignias_usuario drop constraint verificacion_romper;

  -- El camino real: finalizar un entrenamiento dispara 0009, que
  -- registra la XP (1 km = 5 XP), que dispara este trigger. De
  -- paso se otorgan las que quedaron pendientes con la tabla rota.
  insert into entrenamientos (usuario_id, tipo_actividad_id)
    values (v_usuario, v_tipo) returning id into v_entreno;
  update entrenamientos
    set estado = 'finalizado', fecha_fin = now(),
        duracion_segundos = 600, distancia_total_m = 1000
    where id = v_entreno;
  v_total := v_total + 5;

  select coalesce(sum(cantidad), 0) into v_n from experiencia_ganada where usuario_id = v_usuario;
  if v_n <> v_total then
    raise exception 'FALLÓ camino real: al finalizar quedó % XP, esperaba %', v_n, v_total;
  end if;
  select count(*) into v_tiene from insignias_usuario where usuario_id = v_usuario;
  select count(*) into v_esperadas from insignias where xp_requerida <= v_total;
  if v_tiene <> v_esperadas then
    raise exception 'FALLÓ camino real: tiene % insignias, esperaba %', v_tiene, v_esperadas;
  end if;

  -- Decisión del equipo: borrar los entrenamientos se lleva su XP
  -- (cascade), pero las insignias se conservan.
  delete from entrenamientos where usuario_id = v_usuario;
  select coalesce(sum(cantidad), 0) into v_n from experiencia_ganada where usuario_id = v_usuario;
  if v_n <> 0 then
    raise exception 'FALLÓ conservar: tras borrar los entrenamientos quedan % XP, el caso no se probó', v_n;
  end if;
  select count(*) into v_n from insignias_usuario where usuario_id = v_usuario;
  if v_n <> v_tiene then
    raise exception 'FALLÓ conservar: al perder la XP quedaron % insignias, esperaba %', v_n, v_tiene;
  end if;

  -- RLS como el dueño: ve las suyas y el catálogo, y no puede
  -- tocar nada. En update y delete RLS no da error: deja 0 filas.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_usuario, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from insignias_usuario where usuario_id = v_usuario;
  if v_n <> v_tiene then
    raise exception 'FALLÓ RLS: el dueño ve % de sus % insignias', v_n, v_tiene;
  end if;
  select count(*) into v_n from insignias;
  if v_n <> v_catalogo then
    raise exception 'FALLÓ RLS: el usuario ve % insignias del catálogo, esperaba %', v_n, v_catalogo;
  end if;

  begin
    update insignias_usuario set fecha_obtencion = '2000-01-01' where usuario_id = v_usuario;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el usuario cambió la fecha de % insignias', v_n; end if;

  begin
    delete from insignias_usuario where usuario_id = v_usuario;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el usuario borró % insignias', v_n; end if;

  begin
    update insignias set xp_requerida = 1;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el usuario editó % insignias del catálogo', v_n; end if;

  begin
    insert into insignias (nombre, descripcion, icono, xp_requerida)
      values ('Trampa', 'No debería existir', 'huella', 1);
    raise exception 'FALLÓ RLS: el usuario creó una insignia en el catálogo';
  exception when insufficient_privilege then
    null; -- esperado
  end;

  begin
    insert into insignias_usuario (usuario_id, insignia_id, xp_al_obtener)
      select v_usuario, id, 0 from insignias order by xp_requerida desc limit 1;
    raise exception 'FALLÓ RLS: el usuario se dio una insignia a sí mismo';
  exception when insufficient_privilege then
    null; -- esperado
  end;

  -- RLS como otro usuario: no ve las ajenas.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  select count(*) into v_n from insignias_usuario where usuario_id = v_usuario;
  if v_n <> 0 then raise exception 'FALLÓ RLS: otro usuario ve % insignias ajenas', v_n; end if;

  -- Sin sesión (anon) no ve ni el catálogo.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
  begin
    select count(*) into v_n from insignias;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: sin sesión se ven % insignias', v_n; end if;

  reset role;

  raise exception 'VERIFICACIÓN OK: criterios 1 a 5, camino real, tolerancia, insignias conservadas y RLS. (Este error deshace los datos de prueba.)';
end;
$$;
*/
