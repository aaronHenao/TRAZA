-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-259 (HU-35): revisar la clasificación
-- de una ruta
--
-- En el flujo de 0048, un Runner Experto asigna la dificultad al
-- aprobar la ruta (`clasificar_ruta`) y el autor la publica. HU-35 es
-- la revisión de esa clasificación, y el equipo acordó que la haga el
-- mismo Runner Experto que la clasificó: con la ruta ya publicada, la
-- confirma o la corrige, y lo que deje es la clasificación definitiva
-- (criterios 3 y 4). El detalle de la ruta dice que la revisó un
-- Runner Experto, y cuándo (criterio 5).
--
-- La app ya llama a confirmar y corregir desde SCRUM-262 y SCRUM-263.
--
-- Decisiones:
--
--   · Quién revisa (`puede_revisar_clasificacion`, la de 0042, ahora
--     más estricta): el Runner Experto que la clasificó, en una ruta
--     publicada, con dificultad y sin revisar. Se revisa una sola vez:
--     eso es que quede "definitiva".
--
--   · No cambia el flujo de 0043 a 0048 ni la tabla `rutas`: la
--     revisión vive en su propia tabla, `revisiones_clasificacion`, con
--     una fila por ruta. Corregir sí cambia `rutas.dificultad`, porque
--     esa es la clasificación que ve todo el mundo, pero por una
--     función, como `clasificar_ruta`.
--
--   · `revisiones_clasificacion` no se lee ni se escribe desde la app:
--     no tiene policies. La escriben las dos funciones de abajo, y la
--     app pregunta la fecha con `clasificacion_revisada_en`. Quién la
--     revisó no sale de la base, porque el criterio 5 dice que fue un
--     Runner Experto, no cuál: queda para auditar, con la dificultad
--     que tenía antes.
--
--   · Revisar no le avisa al autor: HU-35 no lo pide.
--
--   · Errores, los que la app ya entiende:
--       42501  no puede revisar esa ruta, o ya no: ya se revisó
--       22023  la dificultad no es facil, moderada ni dificil
--
-- Corre esto DESPUÉS de 0048_flujo_unico_de_revision.sql.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. La revisión de cada ruta: una sola
-- -------------------------------------------------------------
create table public.revisiones_clasificacion (
  -- Una fila por ruta: una clasificación se revisa una sola vez.
  ruta_id              uuid primary key references public.rutas(id) on delete cascade,
  -- Si su cuenta se borra, la revisión se queda.
  revisor_id           uuid references auth.users(id) on delete set null,
  -- La que tenía la ruta: si es la misma que `dificultad`, la confirmó.
  dificultad_anterior  text not null
    check (dificultad_anterior in ('facil', 'moderada', 'dificil')),
  dificultad           text not null
    check (dificultad in ('facil', 'moderada', 'dificil')),
  fecha                timestamptz not null default now()
);

comment on table public.revisiones_clasificacion is
  'La revisión de la clasificación de cada ruta (SCRUM-259, HU-35): '
  'quién la confirmó o la corrigió, desde qué dificultad y cuándo.';

-- Sin policies: desde la app no se lee ni se escribe directo.
alter table public.revisiones_clasificacion enable row level security;

-- -------------------------------------------------------------
-- 2. Quién puede revisar: la regla de 0042, más estricta
--
-- `create or replace` conserva los permisos que le dio 0042: solo
-- con sesión.
-- -------------------------------------------------------------
create or replace function public.puede_revisar_clasificacion(p_ruta_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.es_experto()
    and exists (
      select 1 from public.rutas r
      where r.id = p_ruta_id
        -- Sin sesión, `auth.uid()` es nulo y las comparaciones no dan
        -- verdadero: también por aquí la respuesta es no.
        and r.autor_id <> auth.uid()
        -- La revisa el mismo Runner Experto que la clasificó.
        and r.clasificada_por = auth.uid()
        and r.estado = 'publicada'
        and r.dificultad is not null
        -- Una vez revisada, es definitiva.
        and not exists (
          select 1 from public.revisiones_clasificacion v
          where v.ruta_id = r.id
        )
    );
$$;

comment on function public.puede_revisar_clasificacion(uuid) is
  'Si quien llama puede revisar la clasificación de la ruta '
  '(SCRUM-260 y SCRUM-259, HU-35): es el Runner Experto que la '
  'clasificó, y la ruta está publicada, con dificultad y sin revisar.';

-- -------------------------------------------------------------
-- 3. Confirmar y corregir (SCRUM-262 y SCRUM-263)
--
-- Las dos dejan la fila de la revisión: quién y cuándo (SCRUM-264).
-- Si la misma ruta se revisa dos veces a la vez (por ejemplo, desde
-- dos teléfonos), la llave de `revisiones_clasificacion` deja pasar
-- la primera y la segunda recibe 42501, como si ya no pudiera.
-- -------------------------------------------------------------
create function public.confirmar_clasificacion(p_ruta_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.puede_revisar_clasificacion(p_ruta_id) then
    raise exception 'No puedes revisar la clasificación de esta ruta'
      using errcode = '42501';
  end if;

  insert into revisiones_clasificacion (ruta_id, revisor_id, dificultad_anterior, dificultad)
  select id, auth.uid(), dificultad, dificultad
  from rutas
  where id = p_ruta_id;
exception
  when unique_violation then
    raise exception 'Esta clasificación ya se revisó'
      using errcode = '42501';
end;
$$;

create function public.corregir_clasificacion(p_ruta_id uuid, p_dificultad text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.puede_revisar_clasificacion(p_ruta_id) then
    raise exception 'No puedes revisar la clasificación de esta ruta'
      using errcode = '42501';
  end if;

  if p_dificultad is null or p_dificultad not in ('facil', 'moderada', 'dificil') then
    raise exception 'La dificultad tiene que ser facil, moderada o dificil'
      using errcode = '22023';
  end if;

  insert into revisiones_clasificacion (ruta_id, revisor_id, dificultad_anterior, dificultad)
  select id, auth.uid(), dificultad, p_dificultad
  from rutas
  where id = p_ruta_id;

  update rutas
  set dificultad = p_dificultad
  where id = p_ruta_id;
exception
  when unique_violation then
    raise exception 'Esta clasificación ya se revisó'
      using errcode = '42501';
end;
$$;

-- -------------------------------------------------------------
-- 4. Cuándo se revisó, para el detalle de la ruta (criterio 5)
--
-- Solo la fecha: quién fue no sale de la base. Las revisiones son
-- de rutas publicadas, que ve cualquier usuario con sesión.
-- -------------------------------------------------------------
create function public.clasificacion_revisada_en(p_ruta_id uuid)
returns timestamptz
language sql
stable
security definer set search_path = public
as $$
  select fecha from public.revisiones_clasificacion where ruta_id = p_ruta_id;
$$;

comment on function public.confirmar_clasificacion(uuid) is
  'El Runner Experto que clasificó una ruta publicada confirma su '
  'dificultad, que queda como definitiva (SCRUM-262, HU-35).';
comment on function public.corregir_clasificacion(uuid, text) is
  'El Runner Experto que clasificó una ruta publicada le pone otra '
  'dificultad, que queda como definitiva (SCRUM-263, HU-35).';
comment on function public.clasificacion_revisada_en(uuid) is
  'Cuándo se revisó la clasificación de una ruta, o nulo si no se ha '
  'revisado (SCRUM-264, HU-35).';

-- Solo quien tiene sesión. Adentro cada una revisa quién es.
revoke all on function public.confirmar_clasificacion(uuid) from public, anon;
revoke all on function public.corregir_clasificacion(uuid, text) from public, anon;
revoke all on function public.clasificacion_revisada_en(uuid) from public, anon;
grant execute on function public.confirmar_clasificacion(uuid) to authenticated;
grant execute on function public.corregir_clasificacion(uuid, text) to authenticated;
grant execute on function public.clasificacion_revisada_en(uuid) to authenticated;

commit;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Lleva rutas por el flujo de 0048 hasta publicarlas y las revisa.
-- Al final lanza un error A PROPÓSITO para que todo se deshaga: no
-- deja nada en la base. El resultado es el mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor      uuid := gen_random_uuid();
  v_admin      uuid := gen_random_uuid();
  v_clasifica  uuid := gen_random_uuid();
  v_otro       uuid := gen_random_uuid();
  v_corredor   uuid := gen_random_uuid();
  v_tipo       uuid := (select id from tipos_actividad limit 1);
  v_e1         uuid;
  v_e2         uuid;
  v_e3         uuid;
  v_e4         uuid;
  v_confirmar  uuid;
  v_corregir   uuid;
  v_sin        uuid;
  v_rara       uuid;
  v_revision   revisiones_clasificacion;
  v_fila       rutas;
  v_avisos     integer;
  v_n          integer;
  v_trazado    jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                          {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,     'prueba-revision-' || v_autor     || '@traza.test'),
    (v_admin,     'prueba-revision-' || v_admin     || '@traza.test'),
    (v_clasifica, 'prueba-revision-' || v_clasifica || '@traza.test'),
    (v_otro,      'prueba-revision-' || v_otro      || '@traza.test'),
    (v_corredor,  'prueba-revision-' || v_corredor  || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;
  -- El autor también es Runner Experto: así, que no revise lo suyo es
  -- por ser el autor, no por no tener el rol.
  insert into roles_usuario (usuario_id, rol) values
    (v_autor, 'experto'), (v_clasifica, 'experto'), (v_otro, 'experto');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 5230, 'finalizado') returning id into v_e1;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 3000, 'finalizado') returning id into v_e2;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 4000, 'finalizado') returning id into v_e3;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 4500, 'finalizado') returning id into v_e4;

  -- El autor publica cuatro rutas.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e1, 'Para confirmar', v_trazado) returning id into v_confirmar;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e2, 'Para corregir', v_trazado) returning id into v_corregir;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e3, 'Sin dificultad', v_trazado) returning id into v_sin;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e4, 'Rara', v_trazado) returning id into v_rara;

  -- El administrador aprueba tres; el experto las clasifica.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform public.decidir_revision_ruta(v_confirmar, true, null);
  perform public.decidir_revision_ruta(v_corregir, true, null);
  perform public.decidir_revision_ruta(v_rara, true, null);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_clasifica, 'role', 'authenticated')::text, true);
  perform public.clasificar_ruta(v_confirmar, 'moderada');
  perform public.clasificar_ruta(v_corregir, 'facil');
  perform public.clasificar_ruta(v_rara, 'moderada');

  -- Clasificada pero sin publicar: todavía no se revisa.
  if public.puede_revisar_clasificacion(v_confirmar) then
    raise exception 'FALLÓ: se puede revisar una ruta sin publicar';
  end if;

  -- El autor las publica.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  perform public.confirmar_publicacion_ruta(v_confirmar);
  perform public.confirmar_publicacion_ruta(v_corregir);
  perform public.confirmar_publicacion_ruta(v_rara);

  -- Filas que el flujo no deja, para probar cada condición sola: una
  -- publicada sin dificultad que figura clasificada por el experto.
  reset role;
  update rutas set estado = 'publicada', clasificada_por = v_clasifica where id = v_sin;
  select count(*) into v_avisos from notificaciones
    where entidad_id in (v_confirmar, v_corregir);
  set local role authenticated;

  -- Criterio 1: solo el Runner Experto que la clasificó.
  if public.puede_revisar_clasificacion(v_confirmar) then
    raise exception 'FALLÓ c1: el autor puede revisar su propia ruta';
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  if public.puede_revisar_clasificacion(v_confirmar) then
    raise exception 'FALLÓ c1: un Runner Experto que no la clasificó puede revisar';
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  if public.puede_revisar_clasificacion(v_confirmar) then
    raise exception 'FALLÓ c1: un corredor sin el rol puede revisar';
  end if;
  begin
    perform public.confirmar_clasificacion(v_confirmar);
    raise exception 'FALLÓ c1: un corredor sin el rol confirmó';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_clasifica, 'role', 'authenticated')::text, true);
  if not public.puede_revisar_clasificacion(v_confirmar) then
    raise exception 'FALLÓ c1: quien la clasificó no puede revisar';
  end if;
  if public.puede_revisar_clasificacion(v_sin) then
    raise exception 'FALLÓ: se puede revisar una ruta sin dificultad';
  end if;

  -- Aunque una fila dijera que la clasificó su autor, o alguien sin el
  -- rol, ninguno de los dos la revisa.
  reset role;
  update rutas set clasificada_por = v_autor where id = v_rara;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if public.puede_revisar_clasificacion(v_rara) then
    raise exception 'FALLÓ c1: el autor revisa la ruta que figura clasificada por él';
  end if;
  reset role;
  update rutas set clasificada_por = v_corredor where id = v_rara;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if public.puede_revisar_clasificacion(v_rara) then
    raise exception 'FALLÓ c1: alguien sin el rol revisa la ruta que figura clasificada por él';
  end if;

  -- Criterio 3: confirmar deja la dificultad y la revisión.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_clasifica, 'role', 'authenticated')::text, true);
  perform public.confirmar_clasificacion(v_confirmar);
  if public.clasificacion_revisada_en(v_confirmar) is null then
    raise exception 'FALLÓ c5: no dice cuándo se revisó';
  end if;
  if public.clasificacion_revisada_en(v_corregir) is not null then
    raise exception 'FALLÓ c5: dice que se revisó una ruta sin revisar';
  end if;

  -- Definitiva: no se vuelve a revisar.
  if public.puede_revisar_clasificacion(v_confirmar) then
    raise exception 'FALLÓ c4: una clasificación revisada se puede volver a revisar';
  end if;
  begin
    perform public.corregir_clasificacion(v_confirmar, 'dificil');
    raise exception 'FALLÓ c4: se corrigió una clasificación ya revisada';
  exception when insufficient_privilege then null;
  end;

  -- Criterio 4: corregir, solo con una dificultad que exista.
  begin
    perform public.corregir_clasificacion(v_corregir, 'extrema');
    raise exception 'FALLÓ c4: se corrigió con una dificultad que no existe';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.corregir_clasificacion(v_corregir, null);
    raise exception 'FALLÓ c4: se corrigió sin dificultad';
  exception when sqlstate '22023' then null;
  end;
  perform public.corregir_clasificacion(v_corregir, 'dificil');

  -- La revisión no se lee ni se escribe directo desde la app.
  select count(*) into v_n from revisiones_clasificacion;
  if v_n <> 0 then
    raise exception 'FALLÓ: la app lee % revisiones directo', v_n;
  end if;
  begin
    insert into revisiones_clasificacion (ruta_id, revisor_id, dificultad_anterior, dificultad)
      values (v_sin, v_clasifica, 'facil', 'facil');
    raise exception 'FALLÓ: la app escribió una revisión directo';
  exception when insufficient_privilege then null;
  end;
  reset role;

  select * into v_fila from rutas where id = v_confirmar;
  select * into v_revision from revisiones_clasificacion where ruta_id = v_confirmar;
  if v_fila.dificultad is distinct from 'moderada'
     or v_revision.revisor_id is distinct from v_clasifica
     or v_revision.dificultad_anterior is distinct from 'moderada'
     or v_revision.dificultad is distinct from 'moderada' then
    raise exception 'FALLÓ c3: quedó % y la revisión % de % a %', v_fila.dificultad,
      v_revision.revisor_id, v_revision.dificultad_anterior, v_revision.dificultad;
  end if;
  select * into v_fila from rutas where id = v_corregir;
  select * into v_revision from revisiones_clasificacion where ruta_id = v_corregir;
  if v_fila.dificultad is distinct from 'dificil' or v_fila.estado <> 'publicada'
     or v_revision.revisor_id is distinct from v_clasifica
     or v_revision.dificultad_anterior is distinct from 'facil'
     or v_revision.dificultad is distinct from 'dificil' then
    raise exception 'FALLÓ c4: quedó %/% y la revisión % de % a %', v_fila.estado,
      v_fila.dificultad, v_revision.revisor_id, v_revision.dificultad_anterior,
      v_revision.dificultad;
  end if;

  -- Revisar no le manda avisos al autor.
  select count(*) into v_n from notificaciones
    where entidad_id in (v_confirmar, v_corregir);
  if v_n <> v_avisos then
    raise exception 'FALLÓ: revisar mandó % avisos', v_n - v_avisos;
  end if;

  -- Sin sesión no se llaman.
  if has_function_privilege('anon', 'public.confirmar_clasificacion(uuid)', 'execute')
     or has_function_privilege('anon', 'public.corregir_clasificacion(uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.clasificacion_revisada_en(uuid)', 'execute')
     or has_function_privilege('anon', 'public.puede_revisar_clasificacion(uuid)', 'execute') then
    raise exception 'FALLÓ: se puede llamar sin sesión';
  end if;

  raise exception 'VERIFICACIÓN OK: solo el Runner Experto que la clasificó revisa una ruta publicada, una vez; confirmar y corregir la dejan definitiva y la revisión solo la escriben sus funciones. (Este error deshace los datos de prueba.)';
end;
$$;
*/
