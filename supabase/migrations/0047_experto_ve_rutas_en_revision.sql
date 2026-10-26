-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-363: el Runner Experto ve lo que
-- tiene por clasificar
--
-- La base compartida no tenía la policy de 0029 "el runner
-- experto ve las rutas en revision". En su lugar estaba otra,
-- creada a mano y que no está en ninguna migración del repo:
--
--   "el runner experto ve las rutas pendientes de su revision"
--   using (es_experto() and estado = 'revision_experto')
--
-- `revision_experto` no es un estado que admita
-- `rutas_estado_valido`, así que esa policy nunca deja ver nada:
-- la bandeja "Rutas por clasificar" salía vacía (lo detectó el
-- script de verificación de 0045).
--
-- Esto vuelve a poner la de 0029 tal cual. La otra no se toca:
-- no sabemos quién la creó ni para qué, y como las policies de
-- select se suman (OR), no estorba. Hay que preguntarlo en el
-- grupo antes de borrarla.
--
-- Corre esto DESPUÉS de 0046_rutas_sin_relleno.sql.
-- =============================================================

begin;

drop policy if exists "el runner experto ve las rutas en revision" on rutas;

create policy "el runner experto ve las rutas en revision"
  on rutas for select
  using (public.es_experto() and estado = 'en_revision');

commit;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Un experto ve la ruta ajena en revisión y no la que tiene la
-- dificultad pendiente; un corredor sin el rol no ve ninguna. Al
-- final lanza un error A PROPÓSITO para que todo se deshaga.
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
--
-- Después de este, vuelve a correr el de 0045: tiene que dar OK.
-- =============================================================
/*
do $$
declare
  v_autor       uuid := gen_random_uuid();
  v_experto     uuid := gen_random_uuid();
  v_otro        uuid := gen_random_uuid();
  v_tipo        uuid := (select id from tipos_actividad limit 1);
  v_con_dist    uuid;
  v_sin_dist    uuid;
  v_ruta        uuid;
  v_incompleta  uuid;
  v_n           integer;
  v_trazado     jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                           {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,   'prueba-bandeja-' || v_autor   || '@traza.test'),
    (v_experto, 'prueba-bandeja-' || v_experto || '@traza.test'),
    (v_otro,    'prueba-bandeja-' || v_otro    || '@traza.test');
  insert into roles_usuario (usuario_id, rol) values (v_experto, 'experto');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 5230, 'finalizado') returning id into v_con_dist;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, null, 'finalizado') returning id into v_sin_dist;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_con_dist, 'Prueba bandeja', v_trazado) returning id into v_ruta;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_sin_dist, 'Prueba bandeja sin distancia', v_trazado)
    returning id into v_incompleta;

  -- El experto ve la que está en revisión, no la incompleta.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_experto, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas where id = v_ruta;
  if v_n <> 1 then raise exception 'FALLÓ: el experto no ve la ruta en revisión'; end if;
  select count(*) into v_n from rutas where id = v_incompleta;
  if v_n <> 0 then raise exception 'FALLÓ: el experto ve una ruta sin distancia'; end if;

  -- Un corredor sin el rol no ve ninguna de las dos.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas where id in (v_ruta, v_incompleta);
  if v_n <> 0 then raise exception 'FALLÓ: un corredor sin el rol ve % rutas sin publicar', v_n; end if;

  reset role;

  raise exception 'VERIFICACIÓN OK: el Runner Experto ve lo que tiene por clasificar. (Este error deshace los datos de prueba.)';
end;
$$;
*/
