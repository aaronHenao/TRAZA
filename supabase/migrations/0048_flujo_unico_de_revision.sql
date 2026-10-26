-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-363 + SCRUM-321: un solo flujo para
-- revisar una ruta
--
-- SCRUM-321 (el administrador revisa primero y después un Runner
-- Experto) y SCRUM-363 (el Runner Experto asigna la dificultad y el
-- autor confirma) describían el mismo tramo de dos formas. Acordado
-- con el equipo, el camino de una ruta queda así:
--
--   publicar ──> en_revision ............ "Pendiente de revisión del
--      │              │                   administrador"
--      │              ├─ admin rechaza ──> rechazada (con motivo)
--      │              └─ admin aprueba
--      │                     v
--      │         revision_experto ....... "Pendiente de revisión del
--      │              │                   Runner Experto"
--      │              ├─ experto rechaza ─> rechazada (con motivo)
--      │              └─ experto aprueba asignando la dificultad
--      │                     v
--      │              clasificada ....... "Lista para publicar"
--      │                     │ el autor confirma
--      │                     v
--      │              publicada
--      └─ sin distancia ──> datos_incompletos (no entra a revisión)
--
-- Las piezas de cada HU:
--
--   · `decidir_revision_ruta` (SCRUM-321): aprobar o rechazar en
--     cada etapa, con motivo obligatorio al rechazar, y su historial
--     en `revisiones_ruta`. Cambia en una sola cosa: el Runner
--     Experto ya no aprueba por aquí, porque aprobar sin dificultad
--     publicaría la ruta sin clasificar y sin que el autor la
--     confirme. Rechazar sí, como antes.
--
--   · `clasificar_ruta` (SCRUM-363, 0045): ES la aprobación del
--     Runner Experto. Ahora parte de `revision_experto` y deja su
--     fila en `revisiones_ruta`, como las otras decisiones.
--
--   · `confirmar_publicacion_ruta` (0045): sin cambios.
--
-- Depende de lo que SCRUM-321 dejó en la base (`revisiones_ruta`,
-- `decidir_revision_ruta`, `avisar_ruta_rechazada`, la policy
-- "el runner experto ve las rutas pendientes de su revision"): su
-- migración tiene que estar en el repo antes que esta.
--
-- Corre esto DESPUÉS de 0047_experto_ve_rutas_en_revision.sql.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. Los estados, con la etapa del experto
-- -------------------------------------------------------------
alter table rutas drop constraint rutas_estado_valido;
alter table rutas
  add constraint rutas_estado_valido
    check (estado in (
      'en_revision', 'revision_experto', 'clasificada', 'publicada',
      'rechazada', 'datos_incompletos'
    ));

-- -------------------------------------------------------------
-- 2. El experto ve lo que espera al experto, no lo del admin
--
-- `en_revision` ahora es la etapa del administrador: la policy de
-- 0029 (repuesta en 0047) se la mostraría a los expertos. La de
-- SCRUM-321 ("...pendientes de su revision", `revision_experto`)
-- es la que les corresponde.
-- -------------------------------------------------------------
drop policy if exists "el runner experto ve las rutas en revision" on rutas;

-- -------------------------------------------------------------
-- 3. La aprobación del experto: asignar la dificultad
--
-- Igual a la de 0045, salvo el estado de partida
-- (`revision_experto`) y la fila en `revisiones_ruta`.
-- -------------------------------------------------------------
create or replace function public.clasificar_ruta(p_ruta_id uuid, p_dificultad text)
returns rutas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_ruta    rutas;
  v_nombre  text;
begin
  if v_usuario is null or not public.es_experto() then
    raise exception 'Solo un Runner Experto clasifica rutas'
      using errcode = '42501';
  end if;

  -- `for update`: si dos expertos la clasifican a la vez, el
  -- segundo espera y luego ve que ya no está esperando al experto.
  select * into v_ruta from rutas where id = p_ruta_id for update;

  if not found or v_ruta.estado <> 'revision_experto' then
    raise exception 'La ruta no está esperando al Runner Experto'
      using errcode = 'TZ409';
  end if;

  if v_ruta.autor_id = v_usuario then
    raise exception 'Un experto no clasifica su propia ruta'
      using errcode = '42501';
  end if;

  update rutas
  set dificultad = p_dificultad,
      clasificada_por = v_usuario,
      estado = 'clasificada'
  where id = p_ruta_id
  returning * into v_ruta;

  -- El historial de la revisión, como deja `decidir_revision_ruta`.
  select coalesce(nullif(btrim(p.nombre), ''), 'Revisor')
    into v_nombre
  from perfiles p
  where p.id = v_usuario;

  insert into revisiones_ruta (ruta_id, revisor_id, revisor_nombre, etapa, decision, motivo)
  values (v_ruta.id, v_usuario, coalesce(v_nombre, 'Revisor'), 'experto', 'aprobada', null);

  perform public.crear_notificacion(
    v_ruta.autor_id,
    'ruta_clasificada',
    'Tu ruta ya tiene dificultad',
    format(
      'Un Runner Experto clasificó «%s» como %s. Confírmala para publicarla.',
      v_ruta.nombre,
      case v_ruta.dificultad
        when 'facil' then 'fácil'
        when 'moderada' then 'moderada'
        else 'difícil'
      end
    ),
    v_ruta.id
  );

  return v_ruta;
end;
$$;

-- -------------------------------------------------------------
-- 4. `decidir_revision_ruta` (SCRUM-321), sin el atajo del experto
--
-- Igual a la que SCRUM-321 dejó en la base, salvo un caso: el
-- Runner Experto aprobando. Ese camino es `clasificar_ruta`.
--
-- Errores (los de SCRUM-321, más uno):
--   23514  rechazar sin motivo, o un motivo de más de 300
--   TZ404  la ruta no existe
--   42501  no le toca esa etapa, o es su propia ruta
--   TZ409  la ruta ya no está esperando esa revisión
--   22023  el experto quiso aprobar sin dificultad
-- -------------------------------------------------------------
create or replace function public.decidir_revision_ruta(
  p_ruta_id uuid,
  p_aprobar boolean,
  p_motivo text
)
returns rutas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ruta rutas;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_etapa text;
  v_siguiente text;
  v_nombre text;
begin
  if not p_aprobar and v_motivo is null then
    raise exception 'Rechazar una ruta exige un motivo' using errcode = '23514';
  end if;

  if v_motivo is not null and length(v_motivo) > 300 then
    raise exception 'El motivo no puede pasar de 300 caracteres'
      using errcode = '23514';
  end if;

  -- `for update`: si el administrador y otro revisor deciden a la
  -- vez, el segundo espera y ve la ruta ya movida (TZ409).
  select * into v_ruta
  from rutas
  where id = p_ruta_id
  for update;

  if v_ruta.id is null then
    raise exception 'La ruta no existe' using errcode = 'TZ404';
  end if;

  if v_ruta.estado = 'en_revision' then
    if not public.es_admin() then
      raise exception 'Solo el administrador hace la primera revisión'
        using errcode = '42501';
    end if;
    v_etapa := 'administrador';
    v_siguiente := 'revision_experto';
  elsif v_ruta.estado = 'revision_experto' then
    if not public.es_experto() then
      raise exception 'Solo un Runner Experto hace la segunda revisión'
        using errcode = '42501';
    end if;
    -- El experto aprueba asignando la dificultad (SCRUM-363), y
    -- después confirma el autor.
    if p_aprobar then
      raise exception 'El Runner Experto aprueba asignando la dificultad (clasificar_ruta)'
        using errcode = '22023';
    end if;
    v_etapa := 'experto';
    v_siguiente := null;
  else
    raise exception 'La ruta ya fue revisada' using errcode = 'TZ409';
  end if;

  -- Nadie aprueba lo suyo: la revisión es de otros ojos.
  if v_ruta.autor_id = auth.uid() then
    raise exception 'No puedes revisar tu propia ruta' using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(p.nombre), ''), 'Revisor')
    into v_nombre
  from perfiles p
  where p.id = auth.uid();

  insert into revisiones_ruta (ruta_id, revisor_id, revisor_nombre, etapa, decision, motivo)
  values (
    v_ruta.id,
    auth.uid(),
    coalesce(v_nombre, 'Revisor'),
    v_etapa,
    case when p_aprobar then 'aprobada' else 'rechazada' end,
    case when p_aprobar then null else v_motivo end
  );

  update rutas
     set estado = case when p_aprobar then v_siguiente else 'rechazada' end,
         motivo_rechazo = case when p_aprobar then null else v_motivo end
   where id = v_ruta.id
  returning * into v_ruta;

  return v_ruta;
end;
$$;

revoke all on function public.decidir_revision_ruta(uuid, boolean, text) from public, anon;
grant execute on function public.decidir_revision_ruta(uuid, boolean, text) to authenticated;

notify pgrst, 'reload schema';

commit;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Recorre el flujo único completo y los rechazos. Al final lanza
-- un error A PROPÓSITO para que todo se deshaga.
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor     uuid := gen_random_uuid();
  v_admin     uuid := gen_random_uuid();
  v_experto   uuid := gen_random_uuid();
  v_tipo      uuid := (select id from tipos_actividad limit 1);
  v_e1        uuid;
  v_e2        uuid;
  v_e3        uuid;
  v_ruta      uuid;
  v_rech_adm  uuid;
  v_rech_exp  uuid;
  v_fila      rutas;
  v_n         integer;
  v_trazado   jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                         {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,   'prueba-flujo-' || v_autor   || '@traza.test'),
    (v_admin,   'prueba-flujo-' || v_admin   || '@traza.test'),
    (v_experto, 'prueba-flujo-' || v_experto || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;
  insert into roles_usuario (usuario_id, rol) values (v_experto, 'experto');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 5230, 'finalizado') returning id into v_e1;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 3000, 'finalizado') returning id into v_e2;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 4000, 'finalizado') returning id into v_e3;

  -- 321 c1: publicar la deja pendiente del administrador.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e1, 'Flujo completo', v_trazado) returning * into v_fila;
  v_ruta := v_fila.id;
  if v_fila.estado <> 'en_revision' then
    raise exception 'FALLÓ 321 c1: nació en %, esperaba en_revision', v_fila.estado;
  end if;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e2, 'La rechaza el admin', v_trazado) returning id into v_rech_adm;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e3, 'La rechaza el experto', v_trazado) returning id into v_rech_exp;

  -- El experto todavía no la ve ni la clasifica.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_experto, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas where id = v_ruta;
  if v_n <> 0 then raise exception 'FALLÓ: el experto ve una ruta que espera al administrador'; end if;
  begin
    perform public.clasificar_ruta(v_ruta, 'facil');
    raise exception 'FALLÓ: el experto clasificó antes que el administrador';
  exception when sqlstate 'TZ409' then null;
  end;

  -- 321 c6: rechazar sin motivo no pasa.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  begin
    perform public.decidir_revision_ruta(v_rech_adm, false, '   ');
    raise exception 'FALLÓ 321 c6: se rechazó sin motivo';
  exception when check_violation then null;
  end;

  -- 321 c3: el admin rechaza con motivo.
  v_fila := public.decidir_revision_ruta(v_rech_adm, false, 'Nombre ofensivo');
  if v_fila.estado <> 'rechazada' then
    raise exception 'FALLÓ 321 c3: quedó %, esperaba rechazada', v_fila.estado;
  end if;

  -- 321 c2: el admin aprueba y pasa al experto.
  v_fila := public.decidir_revision_ruta(v_ruta, true, null);
  if v_fila.estado <> 'revision_experto' then
    raise exception 'FALLÓ 321 c2: quedó %, esperaba revision_experto', v_fila.estado;
  end if;
  perform public.decidir_revision_ruta(v_rech_exp, true, null);

  -- El experto la ve, pero no la aprueba sin dificultad.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_experto, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas where id = v_ruta;
  if v_n <> 1 then raise exception 'FALLÓ: el experto no ve la ruta que lo espera'; end if;
  begin
    perform public.decidir_revision_ruta(v_ruta, true, null);
    raise exception 'FALLÓ: el experto publicó sin asignar la dificultad';
  exception when sqlstate '22023' then null;
  end;

  -- 321 c5: el experto rechaza con motivo.
  v_fila := public.decidir_revision_ruta(v_rech_exp, false, 'Pasa por una vía cerrada');
  if v_fila.estado <> 'rechazada' then
    raise exception 'FALLÓ 321 c5: quedó %, esperaba rechazada', v_fila.estado;
  end if;

  -- 363 c2 / 321 c4: el experto aprueba asignando la dificultad.
  v_fila := public.clasificar_ruta(v_ruta, 'moderada');
  if v_fila.estado <> 'clasificada' or v_fila.dificultad <> 'moderada' then
    raise exception 'FALLÓ: quedó %/%, esperaba clasificada/moderada', v_fila.estado, v_fila.dificultad;
  end if;

  -- Y el autor confirma.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  v_fila := public.confirmar_publicacion_ruta(v_ruta);
  if v_fila.estado <> 'publicada' then
    raise exception 'FALLÓ: quedó %, esperaba publicada', v_fila.estado;
  end if;

  reset role;

  -- El historial tiene las dos aprobaciones y los dos rechazos.
  select count(*) into v_n from revisiones_ruta
    where ruta_id in (v_ruta, v_rech_adm, v_rech_exp);
  if v_n <> 5 then raise exception 'FALLÓ: el historial tiene % decisiones, esperaba 5', v_n; end if;
  select count(*) into v_n from revisiones_ruta
    where ruta_id = v_ruta and etapa = 'experto' and decision = 'aprobada';
  if v_n <> 1 then raise exception 'FALLÓ: la aprobación del experto no quedó en el historial'; end if;

  -- Los avisos: dos rechazos con su motivo, la clasificación y la
  -- publicación.
  select count(*) into v_n from notificaciones
    where usuario_id = v_autor and tipo = 'ruta_rechazada';
  if v_n <> 2 then raise exception 'FALLÓ: el autor recibió % avisos de rechazo, esperaba 2', v_n; end if;
  select count(*) into v_n from notificaciones
    where usuario_id = v_autor and tipo in ('ruta_clasificada', 'ruta_publicada') and entidad_id = v_ruta;
  if v_n <> 2 then raise exception 'FALLÓ: el autor recibió % avisos de la ruta aprobada, esperaba 2', v_n; end if;

  raise exception 'VERIFICACIÓN OK: flujo único (admin, experto con dificultad, autor confirma) y rechazos con motivo. (Este error deshace los datos de prueba.)';
end;
$$;
*/
