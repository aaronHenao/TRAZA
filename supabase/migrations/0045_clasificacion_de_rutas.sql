-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-363: clasificación de la ruta por un
-- Runner Experto
--
-- Antes de publicarse, una ruta pasa por un Runner Experto que le
-- asigna una dificultad (criterio 1). Con la dificultad puesta, el
-- autor confirma y la ruta se publica mostrándola (criterio 2).
-- Si a la ruta le faltan datos para clasificarla, queda registrada
-- con la dificultad pendiente (criterio 3).
--
-- El camino de una ruta:
--
--   en_revision ──(el experto asigna)──> clasificada
--        │                                   │
--        │                         (el autor confirma)
--        │                                   v
--        │                               publicada
--   datos_incompletos: nace así si no tiene distancia y no llega
--   a los expertos.
--
-- Decisiones:
--
--   · "Datos suficientes" es tener la distancia registrada (el
--     trazado de al menos dos puntos ya lo exige 0029). La HU
--     también nombra la pendiente y el desnivel, pero la app no
--     guarda altitud (0001: "puntos_gps SIN altitud, a petición
--     explícita"); acordado con el equipo que el experto clasifica
--     con la distancia y el mapa. Ver docs/deudas.md.
--
--   · Clasificar y confirmar entran por funciones `security
--     definer`, como `decidir_moderacion` en el foro (0035), y no
--     por una policy de update: así cada uno solo cambia lo suyo
--     (el experto la dificultad, el autor el paso a publicada) y
--     nadie toca el nombre, el trazado o el estado a mano.
--
--   · Cualquier experto toma cualquier ruta en revisión: la policy
--     de 0029 ya les deja verlas. Nadie clasifica la suya.
--
--   · `dificultad` usa los valores de `Dificultad`
--     (`lib/models/dificultad.dart`), que la app ya lee y filtra
--     desde SCRUM-275: `facil`, `moderada` y `dificil`.
--
--   · `rutas_cercanas` (0038) y `buscar_rutas` (0041) devuelven ahora
--     también la dificultad, para que el filtro de Explorar rutas
--     funcione con datos de verdad. Cambiar lo que devuelve una
--     función obliga a borrarla y crearla de nuevo, con sus
--     permisos: el cuerpo es el mismo.
--
--   · Rechazar una ruta queda fuera de esta HU (no está en sus
--     criterios).
--
-- Corre esto DESPUÉS de 0041_buscar_por_palabras.sql (y de las
-- migraciones de recompensas, si ya están aplicadas: no dependen
-- una de otra).
-- =============================================================

begin;

-- -------------------------------------------------------------
-- 1. La dificultad y los estados nuevos
-- -------------------------------------------------------------
alter table rutas
  add column dificultad text,
  -- Qué experto la clasificó, para auditar. Si su cuenta se borra,
  -- la dificultad se queda.
  add column clasificada_por uuid references auth.users(id) on delete set null;

alter table rutas
  add constraint rutas_dificultad_valida
    check (dificultad is null or dificultad in ('facil', 'moderada', 'dificil')),
  -- Una ruta clasificada es una ruta con dificultad. (Las publicadas
  -- antes de esta HU no la tienen, así que a ellas no se les exige.)
  add constraint rutas_clasificada_con_dificultad
    check (estado <> 'clasificada' or dificultad is not null);

alter table rutas drop constraint rutas_estado_valido;
alter table rutas
  add constraint rutas_estado_valido
    check (estado in (
      'en_revision', 'clasificada', 'publicada', 'rechazada', 'datos_incompletos'
    ));

-- -------------------------------------------------------------
-- 2. Al crearla: a revisión o con la dificultad pendiente
--    (criterios 1 y 3)
--
-- Igual a la de 0030 —el nombre del autor, el trazado, el punto de
-- inicio y la distancia— más el estado según los datos. Si la
-- vuelves a tocar, parte de esta versión.
-- -------------------------------------------------------------
create or replace function public.preparar_ruta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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

-- Las que ya esperaban revisión sin distancia tampoco le llegan
-- al experto: no habría con qué clasificarlas.
update rutas
set estado = 'datos_incompletos'
where estado = 'en_revision'
  and distancia_km is null;

-- -------------------------------------------------------------
-- 3. El experto asigna la dificultad (criterio 1 → 2)
--
-- Errores que la app traduce:
--   42501  sin sesión, no es Runner Experto, o es su propia ruta
--   TZ409  la ruta ya no está en revisión (otro experto se
--          adelantó, o cambió de estado)
--   23514  la dificultad no es una de las tres
-- -------------------------------------------------------------
create function public.clasificar_ruta(p_ruta_id uuid, p_dificultad text)
returns rutas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_ruta    rutas;
begin
  if v_usuario is null or not public.es_experto() then
    raise exception 'Solo un Runner Experto clasifica rutas'
      using errcode = '42501';
  end if;

  -- `for update`: si dos expertos la clasifican a la vez, el
  -- segundo espera y luego ve que ya no está en revisión.
  select * into v_ruta from rutas where id = p_ruta_id for update;

  if not found or v_ruta.estado <> 'en_revision' then
    raise exception 'La ruta ya no está en revisión' using errcode = 'TZ409';
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
-- 4. El autor confirma y se publica (criterio 2)
--
-- La fecha de publicación la pone `rutas_sellar_publicacion`
-- (0029) y el aviso "Tu ruta ya está publicada",
-- `rutas_avisar_publicacion` (0033): los dos miran el cambio de
-- estado, no quién lo hace.
--
-- Errores que la app traduce:
--   42501  sin sesión, o la ruta no es suya
--   TZ409  la ruta no está esperando su confirmación
-- -------------------------------------------------------------
create function public.confirmar_publicacion_ruta(p_ruta_id uuid)
returns rutas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario uuid := auth.uid();
  v_ruta    rutas;
begin
  if v_usuario is null then
    raise exception 'Hace falta una sesión' using errcode = '42501';
  end if;

  select * into v_ruta from rutas where id = p_ruta_id for update;

  if not found then
    raise exception 'La ruta ya no existe' using errcode = 'TZ409';
  end if;

  if v_ruta.autor_id <> v_usuario then
    raise exception 'Solo el autor publica su ruta' using errcode = '42501';
  end if;

  if v_ruta.estado <> 'clasificada' then
    raise exception 'La ruta no está esperando confirmación'
      using errcode = 'TZ409';
  end if;

  update rutas
  set estado = 'publicada'
  where id = p_ruta_id
  returning * into v_ruta;

  return v_ruta;
end;
$$;

-- Solo quien tiene sesión. Adentro cada una revisa quién es.
revoke all on function public.clasificar_ruta(uuid, text) from public, anon;
revoke all on function public.confirmar_publicacion_ruta(uuid) from public, anon;
grant execute on function public.clasificar_ruta(uuid, text) to authenticated;
grant execute on function public.confirmar_publicacion_ruta(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5. El aviso nuevo
-- -------------------------------------------------------------
alter table notificaciones drop constraint notificaciones_tipo_valido;
alter table notificaciones
  add constraint notificaciones_tipo_valido
    check (tipo in (
      'ruta_publicada', 'ruta_rechazada', 'publicacion_retirada', 'ruta_clasificada'
    ));

-- -------------------------------------------------------------
-- 6. `rutas_cercanas`, ahora con la dificultad
--
-- Igual a la de 0038: mismos parámetros, mismo filtro, mismo
-- orden y misma política de acceso. Lo único nuevo es la columna
-- `dificultad` al final.
-- -------------------------------------------------------------
drop function public.rutas_cercanas(
  double precision, double precision, double precision, integer
);

create function public.rutas_cercanas(
  p_latitud    double precision,
  p_longitud   double precision,
  p_radio_km   double precision default 50,
  p_limite     integer default 50
)
returns table (
  id                   uuid,
  autor_id             uuid,
  autor_nombre         text,
  entrenamiento_id     uuid,
  nombre               text,
  descripcion          text,
  distancia_km         numeric,
  estado               text,
  motivo_rechazo       text,
  fecha_creacion       timestamptz,
  fecha_publicacion    timestamptz,
  distancia_usuario_km double precision,
  miniatura            jsonb,
  dificultad           text
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_radio      double precision;
  v_limite     integer;
  v_delta_lat  double precision;
  v_delta_lng  double precision;
  v_coseno     double precision;
begin
  if p_latitud is null or p_longitud is null
     or p_latitud not between -90 and 90
     or p_longitud not between -180 and 180 then
    raise exception 'coordenadas fuera de rango: (%, %)',
      p_latitud, p_longitud
      using errcode = '22023';
  end if;

  v_radio := least(greatest(coalesce(p_radio_km, 50), 0.1), 500);
  v_limite := least(greatest(coalesce(p_limite, 50), 1), 100);

  -- La caja algo más ancha que el radio, y sin tope de longitud
  -- cerca de los polos: lo mismo que en 0037.
  v_delta_lat := v_radio / 111.045;
  v_coseno := abs(cos(radians(p_latitud)));
  v_delta_lng := case
    when v_coseno < 0.01 then 360
    else least(v_radio / (111.045 * v_coseno), 360)
  end;

  return query
  select
    c.id,
    c.autor_id,
    c.autor_nombre,
    c.entrenamiento_id,
    c.nombre,
    c.descripcion,
    c.distancia_km,
    c.estado,
    c.motivo_rechazo,
    c.fecha_creacion,
    c.fecha_publicacion,
    c.distancia_usuario_km,
    c.miniatura,
    c.dificultad
  from (
    select
      r.id,
      r.autor_id,
      r.autor_nombre,
      r.entrenamiento_id,
      r.nombre,
      r.descripcion,
      r.distancia_km,
      r.estado,
      r.motivo_rechazo,
      r.fecha_creacion,
      r.fecha_publicacion,
      public.distancia_km_entre(
        p_latitud, p_longitud, r.inicio_latitud, r.inicio_longitud
      ) as distancia_usuario_km,
      public.miniatura_de_trazado(r.trazado) as miniatura,
      r.dificultad
    from rutas r
    where r.estado = 'publicada'
      and r.inicio_latitud between p_latitud - v_delta_lat
                               and p_latitud + v_delta_lat
      and (
        v_delta_lng >= 360
        or r.inicio_longitud between p_longitud - v_delta_lng
                                 and p_longitud + v_delta_lng
      )
  ) c
  where c.distancia_usuario_km <= v_radio
  order by c.distancia_usuario_km asc, c.fecha_publicacion desc
  limit v_limite;
end;
$$;

comment on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) is 'Rutas publicadas ordenadas por cercanía a unas coordenadas, con su miniatura y su dificultad (SCRUM-243, SCRUM-247 y SCRUM-363). Respeta RLS: solo devuelve lo publicado.';

-- -------------------------------------------------------------
-- 7. `buscar_rutas`, ahora con la dificultad
--
-- Igual a la de 0041. Lo único nuevo es la columna `dificultad` al
-- final.
-- -------------------------------------------------------------
drop function public.buscar_rutas(
  text,
  double precision, double precision,
  double precision, double precision, double precision, double precision,
  integer
);

create function public.buscar_rutas(
  p_termino    text,
  p_latitud    double precision default null,
  p_longitud   double precision default null,
  p_zona_sur   double precision default null,
  p_zona_oeste double precision default null,
  p_zona_norte double precision default null,
  p_zona_este  double precision default null,
  p_limite     integer default 50
)
returns table (
  id                   uuid,
  autor_id             uuid,
  autor_nombre         text,
  entrenamiento_id     uuid,
  nombre               text,
  descripcion          text,
  distancia_km         numeric,
  estado               text,
  motivo_rechazo       text,
  fecha_creacion       timestamptz,
  fecha_publicacion    timestamptz,
  distancia_usuario_km double precision,
  miniatura            jsonb,
  dificultad           text
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_termino     text := public.texto_para_buscar(p_termino);
  v_palabras    text[] := '{}';
  v_con_texto   boolean;
  v_con_zona    boolean;
  v_con_usuario boolean;
  v_limite      integer;
begin
  if num_nonnulls(p_zona_sur, p_zona_oeste, p_zona_norte, p_zona_este)
     not in (0, 4) then
    raise exception 'la zona necesita sus cuatro bordes'
      using errcode = '22023';
  end if;
  v_con_zona := p_zona_sur is not null;

  if v_con_zona and (
       p_zona_sur not between -90 and 90
    or p_zona_norte not between -90 and 90
    or p_zona_oeste not between -180 and 180
    or p_zona_este not between -180 and 180
    or p_zona_sur > p_zona_norte
    or p_zona_oeste > p_zona_este
  ) then
    raise exception 'zona fuera de rango: sur %, oeste %, norte %, este %',
      p_zona_sur, p_zona_oeste, p_zona_norte, p_zona_este
      using errcode = '22023';
  end if;

  if num_nonnulls(p_latitud, p_longitud) = 1
     or (p_latitud is not null and (
          p_latitud not between -90 and 90
       or p_longitud not between -180 and 180
     )) then
    raise exception 'coordenadas fuera de rango: (%, %)',
      p_latitud, p_longitud
      using errcode = '22023';
  end if;
  v_con_usuario := p_latitud is not null;

  v_con_texto := length(v_termino) >= 2;
  if v_con_texto then
    v_palabras := string_to_array(v_termino, ' ');
  end if;

  if not v_con_texto and not v_con_zona then
    raise exception
      'nada que buscar: hacen falta al menos dos letras o una zona'
      using errcode = '22023';
  end if;

  v_limite := least(greatest(coalesce(p_limite, 50), 1), 100);

  return query
  select
    c.id,
    c.autor_id,
    c.autor_nombre,
    c.entrenamiento_id,
    c.nombre,
    c.descripcion,
    c.distancia_km,
    c.estado,
    c.motivo_rechazo,
    c.fecha_creacion,
    c.fecha_publicacion,
    c.distancia_usuario_km,
    c.miniatura,
    c.dificultad
  from (
    select
      r.id,
      r.autor_id,
      r.autor_nombre,
      r.entrenamiento_id,
      r.nombre,
      r.descripcion,
      r.distancia_km,
      r.estado,
      r.motivo_rechazo,
      r.fecha_creacion,
      r.fecha_publicacion,
      case when v_con_usuario then
        public.distancia_km_entre(
          p_latitud, p_longitud, r.inicio_latitud, r.inicio_longitud
        )
      end as distancia_usuario_km,
      public.miniatura_de_trazado(r.trazado) as miniatura,
      r.dificultad
    from rutas r
    cross join lateral (
      select public.texto_para_buscar(r.nombre || ' ' || r.autor_nombre)
        as texto
    ) t
    where r.estado = 'publicada'
      and (
        -- Por texto: ninguna palabra puede faltar, y cada una tiene
        -- que ser el comienzo de una palabra.
        (v_con_texto and not exists (
          select 1
          from unnest(v_palabras) as palabra
          where strpos(' ' || t.texto, ' ' || palabra) = 0
        ))
        or (v_con_zona
            and r.inicio_latitud between p_zona_sur and p_zona_norte
            and r.inicio_longitud between p_zona_oeste and p_zona_este)
      )
  ) c
  order by c.distancia_usuario_km asc nulls last,
           c.fecha_publicacion desc,
           c.id
  limit v_limite;
end;
$$;

-- Al borrar y crear las dos funciones se pierden sus permisos: se
-- vuelven a dar como en 0038 y 0040 (solo quien tiene sesión).
revoke all on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) from public, anon;
grant execute on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) to authenticated;

revoke all on function public.buscar_rutas(
  text,
  double precision, double precision,
  double precision, double precision, double precision, double precision,
  integer
) from public, anon;
grant execute on function public.buscar_rutas(
  text,
  double precision, double precision,
  double precision, double precision, double precision, double precision,
  integer
) to authenticated;

-- PostgREST guarda qué funciones hay; se le avisa para que vea las
-- nuevas y las que cambiaron sin esperar a que lo note solo.
notify pgrst, 'reload schema';

commit;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un autor, un Runner Experto y otro corredor de prueba, y
-- revisa los criterios 1 a 3 y el RLS. Al final lanza un error A
-- PROPÓSITO para que todo se deshaga: no deja nada en la base (las
-- notificaciones tampoco). El resultado es el mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor        uuid := gen_random_uuid();
  v_experto      uuid := gen_random_uuid();
  v_otro         uuid := gen_random_uuid();
  v_tipo         uuid := (select id from tipos_actividad limit 1);
  v_con_dist     uuid;
  v_sin_dist     uuid;
  v_del_experto  uuid;
  v_ruta         uuid;
  v_incompleta   uuid;
  v_propia       uuid;
  v_fila         rutas;
  v_n            integer;
  v_trazado      jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                            {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,   'prueba-clasificacion-' || v_autor   || '@traza.test'),
    (v_experto, 'prueba-clasificacion-' || v_experto || '@traza.test'),
    (v_otro,    'prueba-clasificacion-' || v_otro    || '@traza.test');
  insert into roles_usuario (usuario_id, rol) values (v_experto, 'experto');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 5230, 'finalizado') returning id into v_con_dist;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, null, 'finalizado') returning id into v_sin_dist;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_experto, v_tipo, 3000, 'finalizado') returning id into v_del_experto;

  -- Criterio 1: con distancia, el autor la publica y queda en
  -- revisión, sin dificultad aunque intente mandarla.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into rutas (autor_id, entrenamiento_id, nombre, trazado, dificultad, estado)
    values (v_autor, v_con_dist, 'Prueba clasificación', v_trazado, 'facil', 'publicada')
    returning * into v_fila;
  v_ruta := v_fila.id;
  if v_fila.estado <> 'en_revision' or v_fila.dificultad is not null then
    raise exception 'FALLÓ criterio 1: nació en % con dificultad %, esperaba en_revision sin dificultad',
      v_fila.estado, v_fila.dificultad;
  end if;

  -- Criterio 3: sin distancia, queda con la dificultad pendiente.
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_sin_dist, 'Prueba sin distancia', v_trazado)
    returning * into v_fila;
  v_incompleta := v_fila.id;
  if v_fila.estado <> 'datos_incompletos' or v_fila.dificultad is not null then
    raise exception 'FALLÓ criterio 3: sin distancia nació en %, esperaba datos_incompletos', v_fila.estado;
  end if;

  -- El autor no la publica sin pasar por el experto.
  begin
    perform public.confirmar_publicacion_ruta(v_ruta);
    raise exception 'FALLÓ criterio 2: se publicó sin clasificar';
  exception when sqlstate 'TZ409' then null;
  end;
  update rutas set estado = 'publicada', dificultad = 'facil' where id = v_ruta;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el autor cambió su ruta a mano'; end if;

  -- Ni se la clasifica él mismo (no es experto).
  begin
    perform public.clasificar_ruta(v_ruta, 'facil');
    raise exception 'FALLÓ RLS: un corredor clasificó una ruta';
  exception when insufficient_privilege then null;
  end;

  -- La ruta del experto, para probar que no clasifica la suya.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_experto, 'role', 'authenticated')::text, true);
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_experto, v_del_experto, 'Ruta del experto', v_trazado)
    returning id into v_propia;

  -- Criterio 1: el experto la ve entre lo que hay por clasificar,
  -- pero no la que tiene la dificultad pendiente.
  select count(*) into v_n from rutas where id = v_ruta and estado = 'en_revision';
  if v_n <> 1 then raise exception 'FALLÓ criterio 1: el experto no ve la ruta en revisión'; end if;
  select count(*) into v_n from rutas where id = v_incompleta;
  if v_n <> 0 then raise exception 'FALLÓ criterio 3: la ruta sin distancia le llegó al experto'; end if;

  begin
    perform public.clasificar_ruta(v_propia, 'facil');
    raise exception 'FALLÓ: un experto clasificó su propia ruta';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.clasificar_ruta(v_ruta, 'imposible');
    raise exception 'FALLÓ: se aceptó una dificultad que no existe';
  exception when check_violation then null;
  end;

  -- Criterio 2: el experto le asigna la dificultad.
  v_fila := public.clasificar_ruta(v_ruta, 'moderada');
  if v_fila.estado <> 'clasificada' or v_fila.dificultad <> 'moderada'
     or v_fila.clasificada_por is distinct from v_experto then
    raise exception 'FALLÓ criterio 2: quedó %/% clasificada por %',
      v_fila.estado, v_fila.dificultad, v_fila.clasificada_por;
  end if;

  -- Otro intento (u otro experto) llega tarde.
  begin
    perform public.clasificar_ruta(v_ruta, 'dificil');
    raise exception 'FALLÓ: se volvió a clasificar una ruta ya clasificada';
  exception when sqlstate 'TZ409' then null;
  end;

  -- Ni otro corredor ni el experto confirman por el autor.
  begin
    perform public.confirmar_publicacion_ruta(v_ruta);
    raise exception 'FALLÓ criterio 2: el experto confirmó por el autor';
  exception when insufficient_privilege then null;
  end;

  -- La comunidad todavía no la ve.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas where id = v_ruta;
  if v_n <> 0 then raise exception 'FALLÓ criterio 2: la comunidad ve una ruta sin confirmar'; end if;

  -- Criterio 2: el autor recibe el aviso, confirma y se publica
  -- con su dificultad.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  select count(*) into v_n from notificaciones
    where usuario_id = v_autor and tipo = 'ruta_clasificada' and entidad_id = v_ruta;
  if v_n <> 1 then raise exception 'FALLÓ criterio 2: el autor no recibió el aviso de la clasificación'; end if;

  v_fila := public.confirmar_publicacion_ruta(v_ruta);
  if v_fila.estado <> 'publicada' or v_fila.dificultad <> 'moderada'
     or v_fila.fecha_publicacion is null then
    raise exception 'FALLÓ criterio 2: quedó % con dificultad % y fecha %',
      v_fila.estado, v_fila.dificultad, v_fila.fecha_publicacion;
  end if;

  -- Criterio 2: la comunidad la ve, con su dificultad, también en
  -- las búsquedas.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  select count(*) into v_n from rutas where id = v_ruta and dificultad = 'moderada';
  if v_n <> 1 then raise exception 'FALLÓ criterio 2: la comunidad no ve la ruta con su dificultad'; end if;
  select count(*) into v_n from public.rutas_cercanas(6.2442, -75.5812, 5, 100)
    where id = v_ruta and dificultad = 'moderada';
  if v_n <> 1 then raise exception 'FALLÓ: rutas_cercanas no devuelve la dificultad'; end if;
  select count(*) into v_n from public.buscar_rutas('prueba')
    where id = v_ruta and dificultad = 'moderada';
  if v_n <> 1 then raise exception 'FALLÓ: buscar_rutas no devuelve la dificultad'; end if;

  -- Sin sesión (anon) no se clasifica ni se confirma.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
  begin
    perform public.clasificar_ruta(v_propia, 'facil');
    raise exception 'FALLÓ RLS: sin sesión se clasificó una ruta';
  exception when insufficient_privilege then null;
  end;

  reset role;

  raise exception 'VERIFICACIÓN OK: criterios 1 a 3 de SCRUM-363 y RLS de la clasificación. (Este error deshace los datos de prueba.)';
end;
$$;
*/
