-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-247 (HU-29): la miniatura de la ruta
--
-- Las tarjetas de Explorar rutas y del carrusel de la portada
-- dibujan la forma de cada ruta en pequeño. Para eso no hace
-- falta su trazado entero —hasta 500 puntos, que en un listado
-- de cien rutas serían decenas de miles de coordenadas para
-- pintar recuadros de 76 px—: basta con unos pocos puntos
-- repartidos a lo largo del recorrido.
--
-- Decisiones:
--
--   · La miniatura se calcula al leer, no se guarda. Una columna
--     nueva obligaría a reescribir la tabla de 0029 y a tocar otra
--     vez `preparar_ruta`, que ya cambió dos veces. Una función
--     que recibe la fila —un "campo calculado" de PostgREST— se
--     pide en el `select` como si fuera una columna más y no toca
--     la tabla.
--
--   · Se llama `miniatura` y no `trazado_miniatura` a propósito:
--     las pruebas del repositorio comprueban que ningún listado
--     pida el "trazado", y esto no lo es. Son 32 puntos para
--     dibujar, no el recorrido que se sigue.
--
--   · 32 puntos, siempre con el primero y el último: la forma se
--     reconoce —una vuelta, una ida y vuelta, una subida— y la
--     partida y la llegada quedan donde están.
--
--   · `rutas_cercanas` (0037) devuelve también la miniatura. Como
--     cambia lo que devuelve, hay que borrarla y crearla de nuevo:
--     `create or replace` no deja cambiar el tipo de retorno. Lo
--     de abajo es la función de 0037 con una columna más, nada
--     más. Si la vuelves a tocar, parte de esta versión.
--
--   · Por ese borrar y crear, todo va en una transacción: si algo
--     falla a mitad, la 0037 queda como estaba en vez de quedarse
--     la app sin función.
--
-- Corre esto DESPUÉS de 0037_rutas_cercanas.sql.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- Unos pocos puntos del trazado, repartidos a lo largo de él
--
-- Toma `p_puntos` posiciones a la misma distancia entre sí en el
-- arreglo, empezando en el primero y terminando en el último. Si
-- el trazado ya tiene esos puntos o menos, lo devuelve tal cual.
--
-- `distinct`: con redondeos, dos posiciones pueden caer en el
-- mismo índice; repetir un punto no dibuja nada distinto.
-- -------------------------------------------------------------
create or replace function public.miniatura_de_trazado(
  p_trazado jsonb,
  p_puntos  integer default 32
)
returns jsonb
language sql
immutable
parallel safe
set search_path = public
as $$
  select case
    when p_trazado is null or jsonb_typeof(p_trazado) <> 'array'
      then '[]'::jsonb
    when jsonb_array_length(p_trazado) <= greatest(p_puntos, 2)
      then p_trazado
    else (
      select jsonb_agg(p_trazado -> muestra.indice order by muestra.indice)
      from (
        select distinct round(
          k * (jsonb_array_length(p_trazado) - 1)::numeric
            / (greatest(p_puntos, 2) - 1)
        )::integer as indice
        from generate_series(0, greatest(p_puntos, 2) - 1) as k
      ) as muestra
    )
  end;
$$;

comment on function public.miniatura_de_trazado(jsonb, integer) is
  'Unos pocos puntos de un trazado, repartidos a lo largo de él (SCRUM-247).';

-- -------------------------------------------------------------
-- La miniatura de una ruta, como campo calculado
--
-- PostgREST trata una función que recibe la fila de una tabla
-- como una columna más de esa tabla: `select=nombre,miniatura`
-- devuelve la miniatura de cada ruta sin traer su trazado.
--
-- Es `immutable` porque solo depende de la fila que le llega: no
-- lee ninguna tabla.
-- -------------------------------------------------------------
create or replace function public.miniatura(r public.rutas)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select public.miniatura_de_trazado(r.trazado);
$$;

comment on function public.miniatura(public.rutas) is
  'Campo calculado: la miniatura del trazado de la ruta (SCRUM-247).';

-- -------------------------------------------------------------
-- `rutas_cercanas`, ahora con la miniatura
--
-- Igual a la de 0037: mismos parámetros, mismo filtro, mismo
-- orden y misma política de acceso. Lo único nuevo es la columna
-- `miniatura` al final.
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
  miniatura            jsonb
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

  -- Calificado con el alias por lo mismo que en 0037: los nombres
  -- de lo que devuelve la función también son variables aquí
  -- dentro.
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
    c.miniatura
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
      public.miniatura_de_trazado(r.trazado) as miniatura
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
) is 'Rutas publicadas ordenadas por cercanía a unas coordenadas, con su miniatura (SCRUM-243 y SCRUM-247). Respeta RLS: solo devuelve lo publicado.';

-- -------------------------------------------------------------
-- Quién puede llamarlas
--
-- Las mismas reglas que 0037: solo quien tiene sesión. Al borrar
-- y crear `rutas_cercanas` se pierden sus permisos, así que se
-- vuelven a dar.
-- -------------------------------------------------------------
revoke all on function public.miniatura_de_trazado(jsonb, integer)
  from public;
revoke all on function public.miniatura(public.rutas) from public;
revoke all on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) from public;

grant execute on function public.miniatura_de_trazado(jsonb, integer)
  to authenticated;
grant execute on function public.miniatura(public.rutas) to authenticated;
grant execute on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) to authenticated;

-- PostgREST guarda qué funciones hay; se le avisa para que vea la
-- nueva y la que cambió sin esperar a que lo note solo.
notify pgrst, 'reload schema';

commit;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Ninguna miniatura pasa de 32 puntos, y conservan la partida
--    y la llegada de su trazado:
--
--   select nombre,
--          jsonb_array_length(trazado) as puntos_trazado,
--          jsonb_array_length(public.miniatura(r)) as puntos_miniatura,
--          (trazado -> 0) = (public.miniatura(r) -> 0) as misma_partida,
--          (trazado -> -1) = (public.miniatura(r) -> -1) as misma_llegada
--   from rutas r;
--
--   `puntos_miniatura` tiene que ser 32 o menos, y las dos últimas
--   columnas, `true`.
--
-- 2. Un trazado corto vuelve entero:
--
--   select public.miniatura_de_trazado(
--     '[{"lat":1,"lng":1},{"lat":2,"lng":2}]'::jsonb
--   );
--
-- 3. `rutas_cercanas` sigue igual y trae la miniatura:
--
--   select nombre, round(distancia_usuario_km::numeric, 2) as km,
--          jsonb_array_length(miniatura) as puntos
--   from public.rutas_cercanas(6.2442, -75.5812);
--
--   Las mismas cinco rutas de antes, en el mismo orden.
-- -------------------------------------------------------------
