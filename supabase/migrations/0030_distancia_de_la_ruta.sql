-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-241: la distancia de la ruta
--
-- La distancia se calcula una sola vez, al guardar la ruta, y se
-- queda escrita: SCRUM-240 solo la lee y la muestra.
--
-- Sale del entrenamiento del que nació la ruta, no de medir su
-- trazado. Dos razones:
--
--   · Es el número que el corredor ya vio en su resumen. Medirlo
--     otra vez aquí daría otro, y tendría que explicar por qué su
--     carrera de 10,2 km publica una ruta de 9,8.
--   · `CalculadoraDistancia` descarta el jitter del GPS y lo
--     recorrido en pausa antes de sumar; el trazado guardado,
--     además, viene recortado a 500 puntos. Medir sobre eso sería
--     medir peor con más trabajo.
--
-- Si el entrenamiento no tiene distancia (o ya no existe), la
-- ruta se queda sin ella: `distancia_km` admite nulo justo para
-- eso, y el criterio 4 de SCRUM-240 es el que dice qué enseñarle
-- al usuario en ese caso.
--
-- Ojo, esta función ya se reemplazó una vez: la creó
-- 0029_rutas.sql. Lo de abajo es esa versión más el cálculo de la
-- distancia, no otra cosa. Si la vuelves a tocar, parte de la
-- última versión —es lo que nos costó la lección de las dos
-- 0018 en el Sprint 2.
--
-- Corre esto DESPUÉS de 0029_rutas.sql.
-- =============================================================

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

  new.estado := 'en_revision';
  new.motivo_rechazo := null;
  new.fecha_creacion := now();
  new.fecha_publicacion := null;

  -- La distancia del entrenamiento, en km y con dos decimales,
  -- que es como la app pinta los km en todas las pantallas.
  --
  -- `nullif(..., 0)`: una ruta de cero km no es una ruta, y
  -- `rutas_distancia_valida` solo admite nulo o algo mayor que
  -- cero. Si el entrenamiento no tiene distancia, el select no
  -- asigna nada y la columna se queda en nulo.
  select nullif(round((e.distancia_total_m / 1000.0)::numeric, 2), 0)
    into new.distancia_km
  from entrenamientos e
  where e.id = new.entrenamiento_id;

  return new;
end;
$$;

-- El trigger `rutas_preparar` de 0029 sigue apuntando a esta
-- función: no hace falta recrearlo.

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Con un entrenamiento finalizado tuyo que tenga distancia:
--
--   insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
--   values (
--     (select usuario_id from entrenamientos where id = '<ENTRENAMIENTO>'),
--     '<ENTRENAMIENTO>',
--     'Prueba de distancia',
--     '[{"lat": 6.2442, "lng": -75.5812},
--       {"lat": 6.2450, "lng": -75.5800}]'::jsonb
--   )
--   returning nombre, distancia_km;
--
--   `distancia_km` tiene que ser `distancia_total_m / 1000`
--   redondeado a dos decimales. Para compararlo:
--
--   select distancia_total_m,
--          round((distancia_total_m / 1000.0)::numeric, 2) as esperada
--   from entrenamientos
--   where id = '<ENTRENAMIENTO>';
--
-- 2. Y el caso del criterio 4 de SCRUM-240, con un entrenamiento
--    finalizado SIN distancia (o con 0):
--
--   insert ... 'Prueba sin distancia' ...
--   returning nombre, distancia_km;
--
--   Debe devolver nulo, no un error.
--
-- Para dejar la base limpia:
--
--   delete from rutas
--   where nombre in ('Prueba de distancia', 'Prueba sin distancia');
-- -------------------------------------------------------------
