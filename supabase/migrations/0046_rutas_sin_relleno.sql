-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-363: corrección de seguridad de 0045
--
-- El problema: el nombre de una ruta podía llevar cientos de
-- espacios al final. `rutas_nombre_valido` (0029) mide el nombre
-- ya recortado, así que lo aceptaba, pero se guardaba con el
-- relleno. Cuando un experto lo clasificaba, el aviso al autor
-- (`clasificar_ruta`, 0045) lleva el nombre entre «», pasaba del
-- largo que admite `notificaciones_mensaje_valido` (0032), y la
-- clasificación entera se deshacía. Con unas cien rutas así, la
-- bandeja de todos los expertos (que trae las cien más antiguas)
-- quedaba bloqueada para siempre. El aviso `ruta_publicada`
-- (0033) tenía el mismo riesgo.
--
-- El arreglo: el nombre se guarda recortado (lo recorta la base
-- al crearla) y un `check` impide que vuelva a entrar con relleno.
-- Así mide como mucho 120 caracteres, y los dos avisos caben.
--
-- De paso, una guarda para el futuro: hoy nadie actualiza `rutas`
-- desde la app (no hay policy de update; todo cambio entra por
-- las funciones de 0045). Si algún día se abre una para editar,
-- por ejemplo, la descripción, el estado, la dificultad y quién
-- la clasificó no quedan a la mano del usuario.
--
-- Corre esto DESPUÉS de 0045_clasificacion_de_rutas.sql.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. Los nombres que ya tienen relleno, recortados
-- -------------------------------------------------------------
update rutas
set nombre = btrim(nombre)
where nombre <> btrim(nombre);

alter table rutas
  add constraint rutas_nombre_sin_relleno
    check (nombre = btrim(nombre));

-- -------------------------------------------------------------
-- 2. Al crearla, el nombre se recorta
--
-- Igual a la de 0045, más el recorte del nombre al principio. Si
-- la vuelves a tocar, parte de esta versión.
-- -------------------------------------------------------------
create or replace function public.preparar_ruta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Recortado aquí, el `check` de arriba nunca le salta a la app.
  new.nombre := btrim(new.nombre);

  select coalesce(nullif(btrim(p.nombre), ''), 'Corredor')
    into new.autor_nombre
  from perfiles p
  where p.id = new.autor_id;

  -- Sin perfil (no debería pasar: lo crea handle_new_user).
  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');

  -- Un punto sin coordenadas rompería el mapa de quien siga la
  -- ruta, y el trazado se guarda una sola vez: más vale que no
  -- entre que arreglarlo después.
  if exists (
    select 1
    from jsonb_array_elements(new.trazado) as punto
    where jsonb_typeof(punto -> 'lat') <> 'number'
       or jsonb_typeof(punto -> 'lng') <> 'number'
  ) then
    raise exception
      'el trazado de la ruta tiene puntos sin coordenadas'
      using errcode = '23514';
  end if;

  new.inicio_latitud := (new.trazado -> 0 ->> 'lat')::double precision;
  new.inicio_longitud := (new.trazado -> 0 ->> 'lng')::double precision;

  new.motivo_rechazo := null;
  new.fecha_creacion := now();
  new.fecha_publicacion := null;
  -- La dificultad la pone un experto, nunca el autor.
  new.dificultad := null;
  new.clasificada_por := null;

  -- La distancia del entrenamiento, en km y con dos decimales,
  -- como en 0030. Si el entrenamiento no tiene distancia, la
  -- columna se queda en nulo.
  select nullif(round((e.distancia_total_m / 1000.0)::numeric, 2), 0)
    into new.distancia_km
  from entrenamientos e
  where e.id = new.entrenamiento_id;

  -- Sin distancia no hay con qué clasificarla: se registra con la
  -- dificultad pendiente y no llega a los expertos (criterio 3).
  new.estado := case
    when new.distancia_km is null then 'datos_incompletos'
    else 'en_revision'
  end;

  return new;
end;
$$;

-- -------------------------------------------------------------
-- 3. Lo que un usuario no cambia con un update directo
--
-- Sin `security definer`: mira quién hace el update. Las
-- funciones de 0045 corren como su dueño, así que a ellas no les
-- aplica; a la app (rol `authenticated`), sí.
-- -------------------------------------------------------------
create function public.proteger_ruta()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.autor_id := old.autor_id;
    new.autor_nombre := old.autor_nombre;
    new.entrenamiento_id := old.entrenamiento_id;
    new.trazado := old.trazado;
    new.inicio_latitud := old.inicio_latitud;
    new.inicio_longitud := old.inicio_longitud;
    new.distancia_km := old.distancia_km;
    new.estado := old.estado;
    new.dificultad := old.dificultad;
    new.clasificada_por := old.clasificada_por;
    new.motivo_rechazo := old.motivo_rechazo;
    new.fecha_creacion := old.fecha_creacion;
    new.fecha_publicacion := old.fecha_publicacion;
  end if;
  return new;
end;
$$;

create trigger rutas_proteger
  before update on rutas
  for each row execute function public.proteger_ruta();

-- Solo la usa el trigger. Nadie la llama directo.
revoke execute on function public.proteger_ruta()
  from public, anon, authenticated;

commit;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Revisa el arreglo y completa lo que no probaba el script de
-- 0045. Al final lanza un error A PROPÓSITO para que todo se
-- deshaga: no deja nada en la base. El resultado es el mensaje de
-- ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor       uuid := gen_random_uuid();
  v_experto     uuid := gen_random_uuid();
  v_otro        uuid := gen_random_uuid();
  v_tipo        uuid := (select id from tipos_actividad limit 1);
  v_e1          uuid;
  v_e2          uuid;
  v_e3          uuid;
  v_e4          uuid;
  v_ruta        uuid;
  v_incompleta  uuid;
  v_fila        rutas;
  v_n           integer;
  v_trazado     jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                           {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,   'prueba-relleno-' || v_autor   || '@traza.test'),
    (v_experto, 'prueba-relleno-' || v_experto || '@traza.test'),
    (v_otro,    'prueba-relleno-' || v_otro    || '@traza.test');
  insert into roles_usuario (usuario_id, rol) values (v_experto, 'experto');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 5230, 'finalizado') returning id into v_e1;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 4, 'finalizado') returning id into v_e2;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 5, 'finalizado') returning id into v_e3;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 0, 'finalizado') returning id into v_e4;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- El arreglo: el relleno no entra, y la ruta se puede clasificar.
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e1, 'X' || repeat(' ', 480), v_trazado)
    returning * into v_fila;
  v_ruta := v_fila.id;
  if v_fila.nombre <> 'X' then
    raise exception 'FALLÓ: el nombre se guardó con % caracteres, esperaba 1', length(v_fila.nombre);
  end if;

  -- El umbral de la distancia: menos de 5 m es "sin distancia".
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e2, 'Cuatro metros', v_trazado) returning * into v_fila;
  v_incompleta := v_fila.id;
  if v_fila.estado <> 'datos_incompletos' then
    raise exception 'FALLÓ criterio 3: con 4 m quedó %, esperaba datos_incompletos', v_fila.estado;
  end if;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e3, 'Cinco metros', v_trazado) returning * into v_fila;
  if v_fila.estado <> 'en_revision' then
    raise exception 'FALLÓ criterio 1: con 5 m quedó %, esperaba en_revision', v_fila.estado;
  end if;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e4, 'Cero metros', v_trazado) returning * into v_fila;
  if v_fila.estado <> 'datos_incompletos' then
    raise exception 'FALLÓ criterio 3: con 0 m quedó %, esperaba datos_incompletos', v_fila.estado;
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_experto, 'role', 'authenticated')::text, true);

  -- Una ruta con la dificultad pendiente no se clasifica, aunque
  -- la función salte RLS.
  begin
    perform public.clasificar_ruta(v_incompleta, 'facil');
    raise exception 'FALLÓ criterio 3: se clasificó una ruta sin distancia';
  exception when sqlstate 'TZ409' then null;
  end;

  -- La del nombre recortado se clasifica sin problema.
  v_fila := public.clasificar_ruta(v_ruta, 'facil');
  if v_fila.estado <> 'clasificada' then
    raise exception 'FALLÓ: la ruta recortada no se pudo clasificar';
  end if;

  -- Otro corredor no confirma por el autor.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  begin
    perform public.confirmar_publicacion_ruta(v_ruta);
    raise exception 'FALLÓ criterio 2: otro corredor confirmó por el autor';
  exception when insufficient_privilege then null;
  end;

  -- El autor confirma una vez; la segunda llega tarde.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  v_fila := public.confirmar_publicacion_ruta(v_ruta);
  if v_fila.estado <> 'publicada' then
    raise exception 'FALLÓ criterio 2: quedó %, esperaba publicada', v_fila.estado;
  end if;
  begin
    perform public.confirmar_publicacion_ruta(v_ruta);
    raise exception 'FALLÓ criterio 2: se confirmó dos veces';
  exception when sqlstate 'TZ409' then null;
  end;

  reset role;

  -- Sin sesión nadie puede llamar las funciones, ni siquiera para
  -- que fallen adentro.
  select count(*) into v_n
  from (values
    ('public.clasificar_ruta(uuid,text)'),
    ('public.confirmar_publicacion_ruta(uuid)'),
    ('public.rutas_cercanas(double precision,double precision,double precision,integer)'),
    ('public.buscar_rutas(text,double precision,double precision,double precision,double precision,double precision,double precision,integer)'),
    ('public.proteger_ruta()')
  ) as f(firma)
  where has_function_privilege('anon', f.firma, 'execute');
  if v_n <> 0 then raise exception 'FALLÓ: % funciones se pueden llamar sin sesión', v_n; end if;

  -- Ninguna ruta guardada tiene relleno.
  select count(*) into v_n from rutas where nombre <> btrim(nombre);
  if v_n <> 0 then raise exception 'FALLÓ: quedan % rutas con relleno en el nombre', v_n; end if;

  raise exception 'VERIFICACIÓN OK: nombres sin relleno, umbral de distancia, una sola confirmación y permisos. (Este error deshace los datos de prueba.)';
end;
$$;
*/
