-- =============================================================
-- TRAZA — Rutas oficiales, etapa 1 (docs/roadmap_mapa_rutas_oficiales.md)
--
-- El mapa de progresión pasa a ser un camino de rutas oficiales:
-- rutas que los corredores publicaron y que el administrador
-- eligió y ordenó. Esta migración guarda cuáles son y en qué
-- posición del camino va cada una.
--
-- Decisiones:
--
--   · La fila apunta a la ruta, no la copia. Ser oficial no cambia
--     su estado, su revisión ni su autor: sigue siendo la misma
--     ruta publicada que se ve en Explorar.
--
--   · Nadie escribe la tabla directo, ni el administrador. Agregar,
--     mover y quitar reacomodan las posiciones de las demás, y eso
--     tiene que pasar en una sola transacción para no dejar huecos
--     ni posiciones repetidas. Por eso van en funciones
--     `security definer` que exigen `es_admin()` (0005).
--
--   · `posicion` es única y `deferrable initially deferred`: mover
--     una ruta corre las demás una posición, y en medio de ese
--     update dos filas comparten número. La unicidad se comprueba
--     al terminar la transacción, cuando ya no.
--
--   · Un candado de transacción (`pg_advisory_xact_lock`) pone en
--     fila los cambios: si dos pestañas del administrador agregan a
--     la vez, las dos calcularían la misma posición final.
--
--   · Quitar sí borra la fila: lo que el corredor ya corrió se
--     guarda aparte (etapa 2, `rutas_completadas`), así que no se
--     pierde historial.
--
--   · `on delete cascade` hacia `rutas`: si una ruta llegara a
--     borrarse (por ejemplo, al borrar la cuenta de su autor desde
--     el dashboard), deja de ser oficial. Un trigger por sentencia
--     renumera después de cualquier borrado, venga de
--     `quitar_ruta_oficial` o de esa cascada: el camino nunca queda
--     con huecos.
--
--   · El corredor lee solo `ruta_id`, `posicion` y
--     `fecha_agregada`. `agregada_por` delataría cuál es la cuenta
--     del administrador.
--
-- Códigos de error que traduce `SupabaseRutasOficialesRepository`:
--   42501  no es administrador
--   22023  la ruta no está publicada
--   TZ409  la ruta ya es oficial
--   TZ404  la ruta no existe (agregar), o ya no es oficial (mover
--          y quitar)
--
-- Corre esto DESPUÉS de 0057_avisos_del_estado_de_la_ruta.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La tabla
-- -------------------------------------------------------------
create table rutas_oficiales (
  ruta_id         uuid primary key references rutas(id) on delete cascade,
  posicion        integer not null,
  agregada_por    uuid references auth.users(id) on delete set null,
  fecha_agregada  timestamptz not null default now(),
  constraint rutas_oficiales_posicion_valida check (posicion >= 1),
  constraint rutas_oficiales_posicion_unica unique (posicion)
    deferrable initially deferred
);

comment on table rutas_oficiales is
  'Rutas publicadas que el administrador eligió para el mapa de '
  'progresión, con su posición en el camino (1 = la primera).';

-- -------------------------------------------------------------
-- 2. RLS
--
-- Lectura: el mapa lo ve cualquier usuario con sesión. La ruta
-- embebida pasa por el RLS de `rutas`, que ya muestra las
-- publicadas a todos (0029).
--
-- Escritura: ninguna policy. Además se quita el privilegio, como
-- en 0056: si mañana alguien escribe una policy de más, el
-- privilegio ya no está.
--
-- La lectura también va por columnas: sin `agregada_por`. Se
-- quita el `select` de la tabla entera, porque revocar una sola
-- columna no sirve mientras el rol tenga el privilegio sobre toda
-- la tabla.
-- -------------------------------------------------------------
alter table rutas_oficiales enable row level security;

create policy "las rutas oficiales las ve cualquier usuario autenticado"
  on rutas_oficiales for select
  to authenticated
  using (true);

revoke all on rutas_oficiales from anon, authenticated;
grant select (ruta_id, posicion, fecha_agregada) on rutas_oficiales to authenticated;

-- -------------------------------------------------------------
-- 2b. Sin huecos después de borrar
--
-- Por sentencia, no por fila: un borrado de varias filas (una
-- cascada) renumera una sola vez. `security definer` porque quien
-- borra puede no tener permiso de escribir la tabla (la cascada
-- corre con el rol de quien borró la ruta).
-- -------------------------------------------------------------
create or replace function public.compactar_rutas_oficiales()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update rutas_oficiales o
    set posicion = n.nueva
    from (
      select ruta_id, row_number() over (order by posicion)::integer as nueva
      from rutas_oficiales
    ) n
    where o.ruta_id = n.ruta_id and o.posicion <> n.nueva;
  return null;
end;
$$;

revoke all on function public.compactar_rutas_oficiales() from public, anon, authenticated;

create trigger rutas_oficiales_sin_huecos
  after delete on rutas_oficiales
  for each statement
  execute function public.compactar_rutas_oficiales();

-- -------------------------------------------------------------
-- 3. Agregar: la ruta queda al final del camino
-- -------------------------------------------------------------
create or replace function public.agregar_ruta_oficial(p_ruta_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador gestiona las rutas oficiales'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('rutas_oficiales'));

  select estado into v_estado from rutas where id = p_ruta_id;

  if v_estado is null then
    raise exception 'La ruta no existe' using errcode = 'TZ404';
  end if;

  if v_estado <> 'publicada' then
    raise exception 'Solo una ruta publicada puede ser oficial'
      using errcode = '22023';
  end if;

  if exists (select 1 from rutas_oficiales where ruta_id = p_ruta_id) then
    raise exception 'La ruta ya es oficial' using errcode = 'TZ409';
  end if;

  insert into rutas_oficiales (ruta_id, posicion, agregada_por)
  select p_ruta_id, coalesce(max(posicion), 0) + 1, auth.uid()
  from rutas_oficiales;
end;
$$;

-- -------------------------------------------------------------
-- 4. Mover: la ruta pasa a [p_posicion] y las del medio se corren
--
-- Una posición fuera del camino se ajusta a la primera o la
-- última: así subir la primera o bajar la última no falla, solo
-- no cambia nada.
-- -------------------------------------------------------------
create or replace function public.mover_ruta_oficial(
  p_ruta_id uuid,
  p_posicion integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual integer;
  v_total integer;
  v_destino integer;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador gestiona las rutas oficiales'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('rutas_oficiales'));

  select posicion into v_actual from rutas_oficiales where ruta_id = p_ruta_id;

  if v_actual is null then
    raise exception 'La ruta no es oficial' using errcode = 'TZ404';
  end if;

  select count(*) into v_total from rutas_oficiales;
  v_destino := greatest(1, least(coalesce(p_posicion, v_actual), v_total));

  if v_destino = v_actual then
    return;
  end if;

  if v_destino < v_actual then
    -- Sube: las que estaban entre el destino y ella bajan una.
    update rutas_oficiales
      set posicion = posicion + 1
      where posicion >= v_destino and posicion < v_actual;
  else
    -- Baja: las que estaban entre ella y el destino suben una.
    update rutas_oficiales
      set posicion = posicion - 1
      where posicion > v_actual and posicion <= v_destino;
  end if;

  update rutas_oficiales set posicion = v_destino where ruta_id = p_ruta_id;
end;
$$;

-- -------------------------------------------------------------
-- 5. Quitar: la ruta sale del mapa y las de atrás suben una
--
-- Las de atrás las sube el trigger de 2b, igual que tras una
-- cascada.
-- -------------------------------------------------------------
create or replace function public.quitar_ruta_oficial(p_ruta_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual integer;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador gestiona las rutas oficiales'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('rutas_oficiales'));

  delete from rutas_oficiales
    where ruta_id = p_ruta_id
    returning posicion into v_actual;

  if v_actual is null then
    raise exception 'La ruta no es oficial' using errcode = 'TZ404';
  end if;
end;
$$;

revoke all on function public.agregar_ruta_oficial(uuid) from public, anon;
revoke all on function public.mover_ruta_oficial(uuid, integer) from public, anon;
revoke all on function public.quitar_ruta_oficial(uuid) from public, anon;
grant execute on function public.agregar_ruta_oficial(uuid) to authenticated;
grant execute on function public.mover_ruta_oficial(uuid, integer) to authenticated;
grant execute on function public.quitar_ruta_oficial(uuid) to authenticated;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un autor, un corredor y un administrador de prueba, tres
-- rutas publicadas y una en revisión, y revisa los criterios de la
-- etapa 1 y el RLS. Al final lanza un error A PROPÓSITO para que
-- todo se deshaga: no deja nada en la base. El resultado es el
-- mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor      uuid := gen_random_uuid();
  v_corredor   uuid := gen_random_uuid();
  v_admin      uuid := gen_random_uuid();
  v_tipo       uuid := (select id from tipos_actividad limit 1);
  v_e          uuid[] := array[]::uuid[];
  v_e_id       uuid;
  v_a          uuid;
  v_b          uuid;
  v_c          uuid;
  v_pendiente  uuid;
  v_orden      text;
  v_n          integer;
  v_trazado    jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                          {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,    'prueba-oficiales-' || v_autor    || '@traza.test'),
    (v_corredor, 'prueba-oficiales-' || v_corredor || '@traza.test'),
    (v_admin,    'prueba-oficiales-' || v_admin    || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;

  for i in 1..4 loop
    insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
      values (v_autor, v_tipo, 3000 + i, 'finalizado') returning id into v_e_id;
    v_e := v_e || v_e_id;
  end loop;

  -- El autor publica cuatro rutas por el flujo normal.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e[1], 'Oficial A', v_trazado) returning id into v_a;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e[2], 'Oficial B', v_trazado) returning id into v_b;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e[3], 'Oficial C', v_trazado) returning id into v_c;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e[4], 'Todavía en revisión', v_trazado) returning id into v_pendiente;

  -- Tres quedan publicadas sin pasar por las dos revisiones: lo que
  -- se prueba aquí es el mapa, no la revisión.
  reset role;
  update rutas
    set estado = 'publicada', fecha_publicacion = now(), dificultad = 'facil'
    where id in (v_a, v_b, v_c);

  -- Criterio 6: un corredor no agrega, no mueve, no quita ni escribe
  -- la tabla directo.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.agregar_ruta_oficial(v_a);
    raise exception 'FALLÓ criterio 6: un corredor agregó una ruta oficial';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into rutas_oficiales (ruta_id, posicion) values (v_a, 1);
    raise exception 'FALLÓ criterio 6: un corredor escribió rutas_oficiales directo';
  exception when insufficient_privilege then null;
  end;
  -- Sin el `revoke`, update y delete no fallarían: afectarían 0
  -- filas en silencio. Lo que se prueba es que el privilegio no está.
  begin
    update rutas_oficiales set posicion = 1 where ruta_id = v_a;
    raise exception 'FALLÓ criterio 6: un corredor pudo hacer update directo';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from rutas_oficiales where ruta_id = v_a;
    raise exception 'FALLÓ criterio 6: un corredor pudo hacer delete directo';
  exception when insufficient_privilege then null;
  end;

  -- Criterio 3: el administrador agrega; cada una queda al final.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform public.agregar_ruta_oficial(v_a);
  perform public.agregar_ruta_oficial(v_b);
  perform public.agregar_ruta_oficial(v_c);

  select string_agg(r.nombre, ',' order by o.posicion) into v_orden
    from rutas_oficiales o join rutas r on r.id = o.ruta_id
    where o.ruta_id in (v_a, v_b, v_c);
  if v_orden <> 'Oficial A,Oficial B,Oficial C' then
    raise exception 'FALLÓ criterio 3: el orden quedó %', v_orden;
  end if;

  -- Criterio 3: una ruta sin publicar o ya oficial no se agrega.
  begin
    perform public.agregar_ruta_oficial(v_pendiente);
    raise exception 'FALLÓ criterio 3: se agregó una ruta en revisión';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.agregar_ruta_oficial(v_a);
    raise exception 'FALLÓ criterio 3: se agregó dos veces la misma ruta';
  exception when sqlstate 'TZ409' then null;
  end;
  begin
    perform public.agregar_ruta_oficial(gen_random_uuid());
    raise exception 'FALLÓ criterio 3: se agregó una ruta que no existe';
  exception when sqlstate 'TZ404' then null;
  end;

  -- Ni el administrador escribe la tabla directo: todo pasa por las
  -- funciones, que mantienen las posiciones.
  begin
    update rutas_oficiales set posicion = 1 where ruta_id = v_c;
    raise exception 'FALLÓ: el administrador pudo hacer update directo';
  exception when insufficient_privilege then null;
  end;

  -- Criterio 4: C sube a la 1; luego A baja más allá del final y
  -- queda última. Siempre 1..n sin huecos.
  perform public.mover_ruta_oficial(v_c, 1);
  select string_agg(r.nombre, ',' order by o.posicion) into v_orden
    from rutas_oficiales o join rutas r on r.id = o.ruta_id
    where o.ruta_id in (v_a, v_b, v_c);
  if v_orden <> 'Oficial C,Oficial A,Oficial B' then
    raise exception 'FALLÓ criterio 4: al subir C quedó %', v_orden;
  end if;

  perform public.mover_ruta_oficial(v_a, 99);
  select string_agg(r.nombre, ',' order by o.posicion) into v_orden
    from rutas_oficiales o join rutas r on r.id = o.ruta_id
    where o.ruta_id in (v_a, v_b, v_c);
  if v_orden <> 'Oficial C,Oficial B,Oficial A' then
    raise exception 'FALLÓ criterio 4: al bajar A al final quedó %', v_orden;
  end if;

  -- Subir la primera (posición 0) o mover a la misma posición no
  -- cambia nada; mover una que no es oficial da TZ404.
  perform public.mover_ruta_oficial(v_c, 0);
  perform public.mover_ruta_oficial(v_b, (select posicion from rutas_oficiales where ruta_id = v_b));
  select string_agg(r.nombre, ',' order by o.posicion) into v_orden
    from rutas_oficiales o join rutas r on r.id = o.ruta_id
    where o.ruta_id in (v_a, v_b, v_c);
  if v_orden <> 'Oficial C,Oficial B,Oficial A' then
    raise exception 'FALLÓ criterio 4: un movimiento sin efecto dejó %', v_orden;
  end if;
  begin
    perform public.mover_ruta_oficial(v_pendiente, 1);
    raise exception 'FALLÓ criterio 4: se movió una ruta que no es oficial';
  exception when sqlstate 'TZ404' then null;
  end;

  -- Criterio 5: quitar B; A sube y no quedan huecos.
  perform public.quitar_ruta_oficial(v_b);
  select count(*) into v_n from rutas_oficiales where ruta_id = v_b;
  if v_n <> 0 then raise exception 'FALLÓ criterio 5: B sigue siendo oficial'; end if;

  -- Las posiciones de toda la tabla son exactamente 1..n. La
  -- unicidad es diferida y el error final deshace todo antes de
  -- comprobarla: se fuerza aquí.
  set constraints rutas_oficiales_posicion_unica immediate;
  select count(*) into v_n from (
    select posicion, row_number() over (order by posicion) as esperada
    from rutas_oficiales
  ) t where posicion <> esperada;
  if v_n <> 0 then
    raise exception 'FALLÓ criterios 4 y 5: hay % posiciones con huecos o repetidas', v_n;
  end if;

  begin
    perform public.quitar_ruta_oficial(v_b);
    raise exception 'FALLÓ criterio 5: se quitó una ruta que ya no era oficial';
  exception when sqlstate 'TZ404' then null;
  end;

  -- Criterio 2 y RLS: el corredor ve el mapa, pero no lo cambia.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas_oficiales where ruta_id in (v_a, v_c);
  if v_n <> 2 then raise exception 'FALLÓ criterio 2: el corredor ve % de 2 rutas oficiales', v_n; end if;
  begin
    perform public.mover_ruta_oficial(v_a, 1);
    raise exception 'FALLÓ criterio 6: un corredor movió una ruta oficial';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.quitar_ruta_oficial(v_a);
    raise exception 'FALLÓ criterio 6: un corredor quitó una ruta oficial';
  exception when insufficient_privilege then null;
  end;
  -- Quién agregó cada ruta no se ve: delataría la cuenta del
  -- administrador.
  begin
    perform agregada_por from rutas_oficiales limit 1;
    raise exception 'FALLÓ: un corredor puede leer agregada_por';
  exception when insufficient_privilege then null;
  end;

  -- Sin sesión (anon) no se lee ni se cambia nada.
  set local role anon;
  begin
    perform 1 from rutas_oficiales limit 1;
    raise exception 'FALLÓ: anon puede leer rutas_oficiales';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.agregar_ruta_oficial(v_b);
    raise exception 'FALLÓ: anon puede agregar rutas oficiales';
  exception when insufficient_privilege then null;
  end;

  -- Un borrado que no pasa por quitar_ruta_oficial (como la cascada
  -- al borrar una ruta) también deja el camino sin huecos.
  reset role;
  delete from rutas_oficiales where ruta_id = v_c;
  set constraints rutas_oficiales_posicion_unica immediate;
  select count(*) into v_n from (
    select posicion, row_number() over (order by posicion) as esperada
    from rutas_oficiales
  ) t where posicion <> esperada;
  if v_n <> 0 then
    raise exception 'FALLÓ: un borrado directo dejó % posiciones con huecos', v_n;
  end if;

  raise exception 'VERIFICACIÓN OK: rutas oficiales cumplen la etapa 1 (todo se deshace)';
end;
$$;
*/
