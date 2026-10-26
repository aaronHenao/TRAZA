-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-243 (HU-29): rutas ordenadas por
-- cercanía
--
-- La consulta que responde "qué rutas tengo cerca": recibe unas
-- coordenadas y devuelve las rutas publicadas de la más cercana
-- a la más lejana, con a cuántos kilómetros queda cada una.
--
-- Decisiones:
--
--   · Sin PostGIS, como decidió 0029. La cercanía se mide con la
--     fórmula del semiverseno (haversine) sobre
--     `inicio_latitud/inicio_longitud`, que esa migración dejó en
--     columnas propias e indexadas pensando en esta HU.
--
--   · Se mide al punto de inicio de la ruta, no al trazado
--     entero. Es lo que el usuario necesita saber —desde dónde
--     arranca y qué tan lejos le queda— y es lo único que el
--     índice puede ordenar sin recorrer cientos de coordenadas
--     por fila.
--
--   · Antes del haversine va un filtro por caja: una resta sobre
--     columnas indexadas descarta casi todo, y la fórmula, que
--     no se puede indexar, solo corre sobre lo que quedó. Con
--     pocas rutas da igual; con muchas es la diferencia entre
--     usar el índice y leer la tabla entera.
--
--   · `security invoker` (el valor por omisión, aquí explícito):
--     la función no se salta RLS, la respeta. Quien la llame ve
--     lo que la policy "las rutas publicadas las ve cualquier
--     usuario autenticado" (0029) le deje ver, y el filtro por
--     estado va además escrito en la consulta para que lo que
--     está en revisión no se le escape a su autor por aquí.
--
--   · Devuelve las mismas columnas que el listado del cliente ya
--     lee, sin `trazado` —un listado no dibuja recorridos— más
--     `distancia_usuario_km`.
--
-- Lo que NO hace esta migración:
--
--   · No calcula el desnivel de la ruta: los puntos GPS que
--     guarda la app no llevan altitud y haría falta un servicio
--     de elevación. El criterio 2 de HU-29 lo pide, así que hay
--     que decidir en el equipo qué se le muestra al usuario
--     mientras tanto.
--   · No sabe de dificultad: esa columna no existe todavía
--     (HU-34).
--   · No busca por texto ni filtra: eso es HU-30, HU-36 y HU-37,
--     y se montan sobre esta misma consulta.
--
-- Corre esto DESPUÉS de 0029_rutas.sql (de ahí salen la tabla,
-- el índice `rutas_inicio_idx` y las policies).
-- =============================================================

-- -------------------------------------------------------------
-- Distancia entre dos puntos, en kilómetros
--
-- Haversine con la Tierra como esfera de radio medio. Para
-- distancias de ciudad el error frente a un elipsoide es de
-- metros: de sobra para ordenar rutas por cercanía.
--
-- `least(1, ...)` antes del asin: con dos puntos casi idénticos
-- la raíz puede pasarse de 1 por redondeo y asin reventaría con
-- un error de dominio.
--
-- Es `immutable`: dos puntos siempre dan lo mismo, así que el
-- planificador puede calcularla una vez y reutilizarla.
-- -------------------------------------------------------------
create or replace function public.distancia_km_entre(
  p_latitud_a  double precision,
  p_longitud_a double precision,
  p_latitud_b  double precision,
  p_longitud_b double precision
)
returns double precision
language sql
immutable
parallel safe
set search_path = public
as $$
  select 2 * 6371.0 * asin(
    least(
      1,
      sqrt(
        power(sin(radians(p_latitud_b - p_latitud_a) / 2), 2)
        + cos(radians(p_latitud_a))
          * cos(radians(p_latitud_b))
          * power(sin(radians(p_longitud_b - p_longitud_a) / 2), 2)
      )
    )
  );
$$;

comment on function public.distancia_km_entre(
  double precision, double precision, double precision, double precision
) is 'Kilómetros en línea recta entre dos coordenadas (haversine).';

-- -------------------------------------------------------------
-- Las rutas publicadas más cercanas a un punto
--
-- `p_radio_km` acota la búsqueda; `p_limite`, cuántas vuelven.
-- Los dos se recortan a un rango sensato en vez de rechazarse:
-- son preferencias de quien consulta, no datos malos. Las
-- coordenadas sí se rechazan, porque una latitud de 200 no es
-- una preferencia, es un error de quien llama.
-- -------------------------------------------------------------
create or replace function public.rutas_cercanas(
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
  distancia_usuario_km double precision
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

  -- Un grado de latitud son ~111,2 km en cualquier parte. Se
  -- divide por un número un pelo menor a propósito: la caja sale
  -- algo más ancha que el radio, y más vale que sobre —el
  -- haversine recorta después— que quedarse corto y perder una
  -- ruta que sí estaba dentro.
  --
  -- Un grado de longitud se encoge al acercarse a los polos, de
  -- ahí el coseno; con el coseno casi en cero la caja se abriría
  -- a medio mundo, así que ahí se deja sin tope y el haversine
  -- hace todo el trabajo.
  v_delta_lat := v_radio / 111.045;
  v_coseno := abs(cos(radians(p_latitud)));
  v_delta_lng := case
    when v_coseno < 0.01 then 360
    else least(v_radio / (111.045 * v_coseno), 360)
  end;

  -- La subconsulta no es adorno: los nombres de las columnas que
  -- devuelve esta función también son variables aquí dentro, y un
  -- `order by distancia_usuario_km` a secas ordenaría por la
  -- variable (vacía) en vez de por la columna. Calificado con el
  -- alias no hay confusión posible.
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
    c.distancia_usuario_km
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
      ) as distancia_usuario_km
    from rutas r
    where r.estado = 'publicada'
      -- El filtro por caja, que es el que usa `rutas_inicio_idx`.
      and r.inicio_latitud between p_latitud - v_delta_lat
                               and p_latitud + v_delta_lat
      and (
        v_delta_lng >= 360
        or r.inicio_longitud between p_longitud - v_delta_lng
                                 and p_longitud + v_delta_lng
      )
  ) c
  -- La distancia de verdad recorta las esquinas de la caja: lo
  -- que queda está dentro del radio, no del cuadrado.
  where c.distancia_usuario_km <= v_radio
  -- A igual distancia, primero lo más reciente: dos rutas que
  -- arrancan en la misma esquina tienen que salir siempre en el
  -- mismo orden, o la lista bailaría entre consultas.
  order by c.distancia_usuario_km asc, c.fecha_publicacion desc
  limit v_limite;
end;
$$;

comment on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) is 'Rutas publicadas ordenadas por cercanía a unas coordenadas (SCRUM-243). Respeta RLS: solo devuelve lo publicado.';

-- -------------------------------------------------------------
-- Quién puede llamarla
--
-- Solo quien tiene sesión. `anon` no entra: en la app no hay
-- ninguna pantalla de rutas sin iniciar sesión, y dejarla
-- abierta regalaría el mapa de por dónde corre la gente.
-- -------------------------------------------------------------
revoke all on function public.distancia_km_entre(
  double precision, double precision, double precision, double precision
) from public;
revoke all on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) from public;

grant execute on function public.distancia_km_entre(
  double precision, double precision, double precision, double precision
) to authenticated;
grant execute on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) to authenticated;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. La distancia da lo que debe. Del estadio Atanasio Girardot
--    al cerro Nutibara hay poco más de un kilómetro:
--
--   select round(public.distancia_km_entre(
--     6.2566, -75.5900,  -- Atanasio
--     6.2447, -75.5847   -- Nutibara
--   )::numeric, 2) as km;
--
--   Tiene que dar alrededor de 1.45.
--
-- 2. Dos puntos iguales dan cero y no revientan:
--
--   select public.distancia_km_entre(6.24, -75.58, 6.24, -75.58);
--
-- 3. Las rutas cercanas salen ordenadas. Desde el centro de
--    Medellín:
--
--   select nombre, round(distancia_usuario_km::numeric, 2) as km
--   from public.rutas_cercanas(6.2442, -75.5812);
--
--   Cada fila tiene que tener un km mayor o igual que la
--   anterior, y ninguna puede estar `en_revision`.
--
-- 4. El radio recorta. Con uno diminuto no debería quedar nada:
--
--   select count(*) from public.rutas_cercanas(6.2442, -75.5812, 0.1);
--
-- 5. Una coordenada imposible se rechaza:
--
--   select * from public.rutas_cercanas(200, -75.5812);
--
--   Tiene que fallar con 22023 y el mensaje de coordenadas
--   fuera de rango.
--
-- 6. No se salta RLS. Desde el SQL Editor se corre como
--    propietario y RLS no aplica, así que esto se prueba desde
--    la app (o con `set local role authenticated`): una ruta en
--    revisión no puede aparecer ni para su propio autor.
-- -------------------------------------------------------------
