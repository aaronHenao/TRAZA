-- =============================================================
-- TRAZA — Rutas oficiales, etapa 4 (docs/roadmap_mapa_rutas_oficiales.md)
--
-- La base decide si un entrenamiento completó la ruta oficial que
-- se estaba corriendo (0060), comparando sus puntos GPS con el
-- trazado de la ruta. Si la completó, la registra en
-- `rutas_completadas` (0059) y el mapa del corredor avanza.
--
-- Completar una ruta da ventaja, así que el cliente no decide
-- nada: solo llama a la función y muestra lo que devuelve.
--
-- La regla:
--
--   Un punto del trazado cuenta como recorrido si algún punto GPS
--   válido del entrenamiento está a 40 m o menos. La ruta queda
--   completada si se recorrió al menos el 90 % de su trazado. El
--   sentido no importa.
--
-- Lo que no se le cree al teléfono (auditorías de seguridad de las
-- etapas 3 y 4):
--
--   · Las horas. Un trigger pone `fecha_inicio` con la hora del
--     servidor al crear el entrenamiento y no deja cambiarla, y
--     guarda en `finalizado_en` la hora del servidor al pasar a
--     `finalizado`. El teléfono sigue mandando `fecha_fin` y la
--     duración para el resumen, pero aquí no se usan.
--
--   · Reabrir. Un entrenamiento finalizado o cancelado ya no cambia
--     de estado desde la app (ella nunca lo hace): si no, uno viejo
--     o descartado se podría "terminar" semanas después para
--     estirar la ventana de la carrera.
--
--   · Que se haya corrido después de que la ruta fuera oficial:
--     `fecha_inicio >= rutas_oficiales.fecha_agregada`.
--
--   · Que haya durado lo que tarda alguien en correr la ruta: a
--     más de 7 m/s (25 km/h) no se corre. La longitud se mide sobre
--     el trazado, que no cambia después de publicar; `distancia_km`
--     puede venir nula o falseada por quien publicó.
--
--   · Los saltos imposibles. Cada punto se compara con el último
--     punto VÁLIDO: si llega a más de 7 m/s, no cuenta. (Compararlo
--     con el anterior tal cual llegó dejaría pasar un señuelo puesto
--     justo antes de cada punto.) Tampoco cuentan los que tienen la
--     hora fuera de la carrera (con 5 minutos de margen por el reloj
--     del teléfono).
--
--   · El tamaño. Se miran como mucho 20 000 puntos, y el trazado y
--     los puntos válidos se calculan una sola vez (`materialized`):
--     sin eso Postgres los relee por cada punto del trazado y una
--     carrera larga tarda segundos.
--
--   · El tiempo. Un `statement_timeout` puesto en la función no
--     corta la sentencia que ya está corriendo; el que manda es el
--     del rol `authenticated` de Supabase.
--
-- Lo que sí puede hacer alguien decidido: un script con su propia
-- sesión que invente puntos sobre el trazado, con horas creíbles,
-- y espere el tiempo real de la carrera. Va a Límites conocidos.
--
-- Errores que traduce `SupabaseRutasOficialesRepository.verificar`:
--   42501  el entrenamiento no existe o es de otro (el mismo error
--          para los dos: no se puede averiguar si un id existe)
--   TZ404  la ruta ya no es oficial
--   TZ422  el recorrido no se puede validar: no ha terminado, se
--          corrió antes de que la ruta fuera oficial, fue más rápido
--          de lo posible, o terminó antes de esta migración
--
-- Corre esto DESPUÉS de 0060_entrenar_una_ruta.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La hora del servidor al terminar
-- -------------------------------------------------------------
alter table entrenamientos
  add column finalizado_en timestamptz;

comment on column entrenamientos.finalizado_en is
  'Hora del servidor en que el entrenamiento pasó a finalizado (rutas '
  'oficiales, etapa 4). La pone un trigger; el cliente no la puede escribir.';

-- -------------------------------------------------------------
-- 2. Las horas y el estado los cuida el servidor
--
-- Solo para lo que llega por la API (`authenticated` y `anon`):
-- PostgREST cambia de rol en cada petición y este trigger corre con
-- el de quien escribe. Los scripts del SQL Editor (rol postgres)
-- pueden fijar las horas, que es lo que usan las verificaciones.
-- -------------------------------------------------------------
create or replace function public.horas_del_servidor()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.fecha_inicio := now();
    new.finalizado_en := case when new.estado = 'finalizado' then now() end;
    return new;
  end if;

  -- Un entrenamiento que ya terminó (finalizado o cancelado) no se
  -- reabre ni se "termina" otra vez. Repetir el mismo estado, como
  -- un cierre reintentado, sí vale.
  if new.estado is distinct from old.estado and old.estado <> 'en_curso' then
    raise exception 'Un entrenamiento terminado no cambia de estado'
      using errcode = '42501';
  end if;

  new.fecha_inicio := old.fecha_inicio;
  new.finalizado_en := case
    when old.finalizado_en is null
         and old.estado is distinct from 'finalizado'
         and new.estado = 'finalizado'
      then now()
    else old.finalizado_en
  end;
  return new;
end;
$$;

create trigger entrenamientos_horas_del_servidor
  before insert or update on entrenamientos
  for each row execute function public.horas_del_servidor();

-- -------------------------------------------------------------
-- 3. La verificación
--
-- Devuelve una fila (cobertura, necesaria, completada), o ninguna
-- si el entrenamiento fue libre. Se puede llamar las veces que
-- haga falta: completar dos veces no duplica (clave primaria de
-- 0059 + `on conflict do nothing`), y si llegan más puntos (el
-- reenvío de SCRUM-292), la siguiente llamada los cuenta.
--
-- `cobertura` va truncada a milésimas (la app muestra el
-- porcentaje hacia abajo); `completada` se decide con la cuenta
-- sin redondear, para que 0.8995 no pase por 0.900.
-- -------------------------------------------------------------
create or replace function public.verificar_ruta_completada(p_entrenamiento_id uuid)
returns table (cobertura numeric, necesaria numeric, completada boolean)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  -- La regla. Para cambiarla, una migración nueva.
  c_necesaria     constant numeric := 0.90;
  c_tolerancia_m  constant double precision := 40;
  c_vel_max_mps   constant double precision := 7;
  c_margen        constant interval := interval '5 minutes';
  c_max_puntos    constant integer := 20000;
  -- Unos 55 m de latitud: el filtro grueso antes de medir.
  c_caja_grados   constant double precision := 0.0005;

  v_e             entrenamientos;
  v_agregada      timestamptz;
  v_trazado       jsonb;
  v_distancia_km  numeric;
  v_longitud_km   double precision;
  v_lat           double precision[] := '{}';
  v_lng           double precision[] := '{}';
  v_n             integer := 0;
  v_ult_lat       double precision;
  v_ult_lng       double precision;
  v_ult_t         timestamptz;
  v_segundos      double precision;
  v_punto         record;
  v_razon         numeric;
begin
  select * into v_e from entrenamientos where id = p_entrenamiento_id;
  if v_e.id is null or v_e.usuario_id is distinct from auth.uid() then
    raise exception 'Entrenamiento no encontrado' using errcode = '42501';
  end if;

  -- Entrenamiento libre: no hay ruta que verificar.
  if v_e.ruta_id is null then
    return;
  end if;

  if v_e.estado <> 'finalizado' or v_e.finalizado_en is null then
    raise exception 'El entrenamiento no ha terminado o no tiene hora del servidor'
      using errcode = 'TZ422';
  end if;

  -- Oficial antes de leer el trazado.
  select o.fecha_agregada into v_agregada
    from rutas_oficiales o where o.ruta_id = v_e.ruta_id;
  if v_agregada is null then
    raise exception 'La ruta ya no es oficial' using errcode = 'TZ404';
  end if;

  select r.trazado, r.distancia_km into v_trazado, v_distancia_km
    from rutas r where r.id = v_e.ruta_id;

  if v_e.fecha_inicio < v_agregada then
    raise exception 'Se corrió antes de que la ruta fuera oficial'
      using errcode = 'TZ422';
  end if;

  -- La longitud del trazado, que no cambia después de publicar.
  select coalesce(sum(distancia_km_entre(lat_ant, lng_ant, lat, lng)), 0)
    into v_longitud_km
    from (
      select (e->>'lat')::double precision as lat,
             (e->>'lng')::double precision as lng,
             lag((e->>'lat')::double precision) over (order by n) as lat_ant,
             lag((e->>'lng')::double precision) over (order by n) as lng_ant
      from jsonb_array_elements(v_trazado) with ordinality as t(e, n)
    ) s
    where lat_ant is not null;

  -- El 90 % del trazado, para no castigar a quien corta una curva.
  if extract(epoch from v_e.finalizado_en - v_e.fecha_inicio)
     < greatest(coalesce(v_distancia_km, 0), 0.9 * v_longitud_km)
       * 1000 / c_vel_max_mps then
    raise exception 'Más rápido de lo posible para esa distancia'
      using errcode = 'TZ422';
  end if;

  -- Los puntos válidos: dentro de la carrera y sin saltos imposibles
  -- respecto al último válido.
  for v_punto in
    select g.latitud, g.longitud, g.capturado_en
    from puntos_gps g
    where g.entrenamiento_id = v_e.id
      and g.capturado_en between v_e.fecha_inicio - c_margen
                             and v_e.finalizado_en + c_margen
    order by g.orden_secuencia
    limit c_max_puntos
  loop
    if v_ult_t is not null then
      v_segundos := extract(epoch from v_punto.capturado_en - v_ult_t);
      if v_segundos <= 0
         or distancia_km_entre(v_ult_lat, v_ult_lng, v_punto.latitud, v_punto.longitud)
            * 1000 / v_segundos > c_vel_max_mps then
        continue;
      end if;
    end if;
    v_n := v_n + 1;
    v_lat[v_n] := v_punto.latitud;
    v_lng[v_n] := v_punto.longitud;
    v_ult_lat := v_punto.latitud;
    v_ult_lng := v_punto.longitud;
    v_ult_t := v_punto.capturado_en;
  end loop;

  with validos as materialized (
    select unnest(v_lat) as latitud, unnest(v_lng) as longitud
  ),
  trazado as materialized (
    select (e->>'lat')::double precision as lat,
           (e->>'lng')::double precision as lng
    from jsonb_array_elements(v_trazado) e
  )
  select coalesce(
           (count(*) filter (where exists (
              select 1 from validos v
              where v.latitud between t.lat - c_caja_grados and t.lat + c_caja_grados
                and v.longitud
                    between t.lng - c_caja_grados / greatest(cos(radians(t.lat)), 0.1)
                        and t.lng + c_caja_grados / greatest(cos(radians(t.lat)), 0.1)
                and distancia_km_entre(t.lat, t.lng, v.latitud, v.longitud) * 1000
                    <= c_tolerancia_m
           )))::numeric / nullif(count(*), 0),
           0)
    into v_razon
  from trazado t;

  cobertura := trunc(v_razon, 3);
  necesaria := c_necesaria;
  completada := v_razon >= c_necesaria;

  if completada then
    insert into rutas_completadas (usuario_id, ruta_id, entrenamiento_id, cobertura)
    values (auth.uid(), v_e.ruta_id, v_e.id, cobertura)
    on conflict (usuario_id, ruta_id) do nothing;
  end if;

  return next;
end;
$$;

revoke all on function public.verificar_ruta_completada(uuid) from public, anon;
grant execute on function public.verificar_ruta_completada(uuid) to authenticated;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Una ruta oficial de 10 puntos en línea recta (unos 500 m) y un
-- corredor que la corre de muchas formas. Al final lanza un error
-- A PROPÓSITO para que todo se deshaga. El resultado es el mensaje
-- de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
--
-- Todo pasa en una transacción, así que now() no avanza. Las horas
-- de cada carrera se fijan como postgres (el trigger no toca ese
-- rol); lo que se prueba como `authenticated` es justamente que el
-- cliente no las pueda fijar.
-- =============================================================
/*
do $$
declare
  v_autor     uuid := gen_random_uuid();
  v_corredor  uuid := gen_random_uuid();
  v_otro      uuid := gen_random_uuid();
  v_tipo      uuid := (select id from tipos_actividad limit 1);
  v_e_ruta    uuid;
  v_ruta      uuid;
  v_e         uuid[] := array[]::uuid[];  -- ver la lista de abajo
  v_id        uuid;
  v_fila      record;
  v_n         integer;
  v_t         timestamptz;
  v_trazado   jsonb;
begin
  -- 10 puntos cada ~55 m hacia el norte.
  select jsonb_agg(jsonb_build_object('lat', 6.2400 + i * 0.0005, 'lng', -75.5800) order by i)
    into v_trazado from generate_series(0, 9) i;

  insert into auth.users (id, email) values
    (v_autor,    'prueba-verificar-' || v_autor    || '@traza.test'),
    (v_corredor, 'prueba-verificar-' || v_corredor || '@traza.test'),
    (v_otro,     'prueba-verificar-' || v_otro     || '@traza.test');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 500, 'finalizado') returning id into v_e_ruta;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e_ruta, 'Recta de prueba', v_trazado) returning id into v_ruta;

  -- Publicada y oficial desde hace una hora. Sin distancia_km, a
  -- propósito: la duración mínima tiene que salir del trazado.
  reset role;
  update rutas
    set estado = 'publicada', fecha_publicacion = now(), dificultad = 'facil',
        distancia_km = null
    where id = v_ruta;
  insert into rutas_oficiales (ruta_id, posicion, fecha_agregada)
    select v_ruta, coalesce(max(posicion), 0) + 1, now() - interval '1 hour'
    from rutas_oficiales;

  -- ---- Lo que el cliente no puede hacer con las horas ni el estado ----
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id, fecha_inicio, finalizado_en)
    values (v_corredor, v_tipo, 'en_curso', v_ruta, now() - interval '3 days', now() + interval '1 day')
    returning id into v_id;
  select count(*) into v_n from entrenamientos
    where id = v_id and fecha_inicio = now() and finalizado_en is null;
  if v_n <> 1 then raise exception 'FALLÓ: el cliente fijó sus horas al crear'; end if;

  -- Al terminar por la API, la hora la pone el servidor.
  update entrenamientos
    set estado = 'finalizado', finalizado_en = now() - interval '1 day'
    where id = v_id;
  select count(*) into v_n from entrenamientos where id = v_id and finalizado_en = now();
  if v_n <> 1 then raise exception 'FALLÓ: el cliente fijó finalizado_en al terminar'; end if;

  -- Terminado al instante: no se valida.
  begin
    perform public.verificar_ruta_completada(v_id);
    raise exception 'FALLÓ: se validó un entrenamiento de cero segundos';
  exception when sqlstate 'TZ422' then
    if sqlerrm not like 'Más rápido%' then raise; end if;
  end;

  -- Ya terminado: no se reabre, ni se vuelve a terminar.
  begin
    update entrenamientos set estado = 'en_curso' where id = v_id;
    raise exception 'FALLÓ: se reabrió un entrenamiento terminado';
  exception when insufficient_privilege then null;
  end;

  -- Uno cancelado tampoco se "termina" después.
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id)
    values (v_corredor, v_tipo, 'en_curso', v_ruta) returning id into v_id;
  update entrenamientos set estado = 'cancelado' where id = v_id;
  begin
    update entrenamientos set estado = 'finalizado' where id = v_id;
    raise exception 'FALLÓ: se terminó un entrenamiento cancelado';
  exception when insufficient_privilege then null;
  end;

  -- Uno en curso no se verifica.
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id)
    values (v_corredor, v_tipo, 'en_curso', v_ruta) returning id into v_id;
  begin
    perform public.verificar_ruta_completada(v_id);
    raise exception 'FALLÓ: se verificó un entrenamiento en curso';
  exception when sqlstate 'TZ422' then
    if sqlerrm not like 'El entrenamiento no ha terminado%' then raise; end if;
  end;

  -- ---- Las carreras: se crean por la API, con puntos del teléfono ----
  -- Índices de v_e:
  --   1 parcial (7/10)   2 ocho (8/10)      3 nueve (9/10)
  --   4 completo (10/10) 5 a 35 m al este   6 a 45 m al este
  --   7 fuera de hora    8 saltos           9 señuelos
  --   10 rápido          11 antes de oficial 12 libre
  for i in 1..12 loop
    insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id)
      values (v_corredor, v_tipo, 'en_curso', case when i = 12 then null else v_ruta end)
      returning id into v_id;
    v_e := v_e || v_id;
  end loop;

  v_t := now() - interval '15 minutes';
  -- Sobre el trazado, cada 30 s (unos 1.8 m/s).
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[1], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(0, 6) i;
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[2], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(0, 7) i;
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[3], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(0, 8) i;
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[4], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(0, 9) i;
  -- A 35 m (cuentan) y a 45 m (no cuentan) del trazado.
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[5], 6.2400 + i * 0.0005, -75.5800 + 0.000317, v_t + i * interval '30 seconds', i
    from generate_series(0, 9) i;
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[6], 6.2400 + i * 0.0005, -75.5800 + 0.000407, v_t + i * interval '30 seconds', i
    from generate_series(0, 9) i;
  -- Bien puestos, pero con la hora de hace dos horas.
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[7], 6.2400 + i * 0.0005, -75.5800, now() - interval '2 hours' + i * interval '30 seconds', i
    from generate_series(0, 9) i;
  -- Cada 1 s: unos 55 m/s. Solo cuenta el primero.
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[8], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '1 second', i
    from generate_series(0, 9) i;
  -- Los mismos saltos, pero con un señuelo en el mismo sitio 0.5 s
  -- antes de cada punto. Comparando con el último válido, no ayuda.
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[9], 6.2400 + (i / 2) * 0.0005, -75.5800,
           v_t + (i / 2) * interval '1 second' - case when i % 2 = 0 then interval '500 milliseconds' else interval '0' end,
           i
    from generate_series(0, 19) i;
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[10], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(0, 9) i;
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[11], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(0, 9) i;

  -- Las horas de cada carrera (como postgres).
  reset role;
  update entrenamientos
    set estado = 'finalizado', fecha_inicio = now() - interval '20 minutes', finalizado_en = now()
    where id = any (v_e[1:9] || v_e[12:12]);
  -- 500 m en 10 s, y la ruta no tiene distancia_km: imposible igual.
  update entrenamientos
    set estado = 'finalizado', fecha_inicio = now() - interval '10 seconds', finalizado_en = now()
    where id = v_e[10];
  -- Empezó antes de que la ruta fuera oficial.
  update entrenamientos
    set estado = 'finalizado', fecha_inicio = now() - interval '2 hours', finalizado_en = now()
    where id = v_e[11];

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- Parcial y ocho de diez: no completan ni registran nada.
  select * into v_fila from public.verificar_ruta_completada(v_e[1]);
  if not found or v_fila.cobertura is distinct from 0.7 or v_fila.completada then
    raise exception 'FALLÓ: 7 de 10 dio %', v_fila;
  end if;
  select * into v_fila from public.verificar_ruta_completada(v_e[2]);
  if not found or v_fila.cobertura is distinct from 0.8 or v_fila.completada then
    raise exception 'FALLÓ: 8 de 10 dio %', v_fila;
  end if;
  select count(*) into v_n from rutas_completadas
    where usuario_id = v_corredor and ruta_id = v_ruta;
  if v_n <> 0 then raise exception 'FALLÓ: un recorrido incompleto registró la ruta'; end if;

  -- Nueve de diez: justo en el umbral, completa y queda registrada.
  select * into v_fila from public.verificar_ruta_completada(v_e[3]);
  if not found or v_fila.cobertura is distinct from 0.9
     or v_fila.necesaria is distinct from 0.9 or not v_fila.completada then
    raise exception 'FALLÓ: 9 de 10 dio %', v_fila;
  end if;
  select count(*) into v_n from rutas_completadas
    where usuario_id = v_corredor and ruta_id = v_ruta
      and entrenamiento_id = v_e[3] and cobertura = 0.9;
  if v_n <> 1 then raise exception 'FALLÓ: la ruta completada no quedó como debía'; end if;

  -- Otra carrera completa de la misma ruta: no duplica.
  select * into v_fila from public.verificar_ruta_completada(v_e[4]);
  if not found or v_fila.cobertura is distinct from 1 or not v_fila.completada then
    raise exception 'FALLÓ: 10 de 10 dio %', v_fila;
  end if;
  select count(*) into v_n from rutas_completadas
    where usuario_id = v_corredor and ruta_id = v_ruta;
  if v_n <> 1 then raise exception 'FALLÓ: completar dos veces duplicó la fila'; end if;

  -- Tolerancia de 40 m.
  select * into v_fila from public.verificar_ruta_completada(v_e[5]);
  if not found or v_fila.cobertura is distinct from 1 then
    raise exception 'FALLÓ: a 35 m no contó: %', v_fila;
  end if;
  select * into v_fila from public.verificar_ruta_completada(v_e[6]);
  if not found or v_fila.cobertura is distinct from 0 then
    raise exception 'FALLÓ: a 45 m contó: %', v_fila;
  end if;

  -- Puntos fuera de la hora de la carrera.
  select * into v_fila from public.verificar_ruta_completada(v_e[7]);
  if not found or v_fila.cobertura is distinct from 0 then
    raise exception 'FALLÓ: contaron puntos fuera de la carrera: %', v_fila;
  end if;

  -- Saltos imposibles, con y sin señuelos: solo el primero.
  select * into v_fila from public.verificar_ruta_completada(v_e[8]);
  if not found or v_fila.cobertura is distinct from 0.1 then
    raise exception 'FALLÓ: los saltos imposibles contaron: %', v_fila;
  end if;
  select * into v_fila from public.verificar_ruta_completada(v_e[9]);
  if not found or v_fila.cobertura is distinct from 0.1 then
    raise exception 'FALLÓ: los señuelos burlaron el filtro de saltos: %', v_fila;
  end if;

  -- Demasiado rápido (sin distancia_km) o antes de ser oficial.
  begin
    perform public.verificar_ruta_completada(v_e[10]);
    raise exception 'FALLÓ: se validó un recorrido imposible de rápido';
  exception when sqlstate 'TZ422' then
    if sqlerrm not like 'Más rápido%' then raise; end if;
  end;
  begin
    perform public.verificar_ruta_completada(v_e[11]);
    raise exception 'FALLÓ: se validó un recorrido anterior a que la ruta fuera oficial';
  exception when sqlstate 'TZ422' then
    if sqlerrm not like 'Se corrió antes%' then raise; end if;
  end;

  -- Libre: ninguna fila.
  select count(*) into v_n from public.verificar_ruta_completada(v_e[12]);
  if v_n <> 0 then raise exception 'FALLÓ: un entrenamiento libre devolvió una verificación'; end if;

  -- Llegan los puntos que faltaban del parcial (el reenvío): ahora
  -- cubre todo.
  insert into puntos_gps (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
    select v_e[1], 6.2400 + i * 0.0005, -75.5800, v_t + i * interval '30 seconds', i
    from generate_series(7, 9) i;
  select * into v_fila from public.verificar_ruta_completada(v_e[1]);
  if not found or v_fila.cobertura is distinct from 1 or not v_fila.completada then
    raise exception 'FALLÓ: con los puntos reenviados dio %', v_fila;
  end if;

  -- El entrenamiento de otro, o uno que no existe: el mismo 42501.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  begin
    perform public.verificar_ruta_completada(v_e[1]);
    raise exception 'FALLÓ: se verificó el entrenamiento de otro';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.verificar_ruta_completada(gen_random_uuid());
    raise exception 'FALLÓ: un id que no existe no dio 42501';
  exception when insufficient_privilege then null;
  end;

  -- Sin sesión no se puede llamar, aunque el entrenamiento sea suyo.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'anon')::text, true);
  set local role anon;
  begin
    perform public.verificar_ruta_completada(v_e[4]);
    raise exception 'FALLÓ: anon puede llamar a verificar_ruta_completada';
  exception when insufficient_privilege then
    if sqlerrm not like 'permission denied for function%' then raise; end if;
  end;

  -- Si la ruta deja de ser oficial, se dice.
  reset role;
  delete from rutas_oficiales where ruta_id = v_ruta;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.verificar_ruta_completada(v_e[2]);
    raise exception 'FALLÓ: se verificó una ruta que ya no es oficial';
  exception when sqlstate 'TZ404' then null;
  end;

  raise exception 'VERIFICACIÓN OK: verificar_ruta_completada cumple la etapa 4 (todo se deshace)';
end;
$$;
*/
