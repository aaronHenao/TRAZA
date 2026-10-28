-- =============================================================
-- TRAZA — SCRUM-292: reenviar puntos GPS sin duplicarlos
-- (subtarea 1, paso 1)
--
-- Hasta ahora los puntos de un entrenamiento se enviaban todos
-- de una vez al finalizar, en un único insert: si fallaba, no se
-- guardaba nada. Ahora se envían por lotes durante la actividad
-- y lo que quede pendiente se reintenta (al finalizar, al volver
-- la red o al abrir la app otra vez).
--
-- Reintentar un lote tiene un riesgo: que el insert llegara a la
-- base y se perdiera la respuesta. El cliente no sabe que entró y
-- lo manda de nuevo, y el recorrido acaba con puntos repetidos.
--
-- Este índice es lo que lo hace imposible. Con él, la app envía
-- los lotes con `on conflict do nothing` (el upsert de PostgREST
-- con `ignoreDuplicates`), así que reenviar un lote que ya estaba
-- guardado no cambia nada y tampoco falla.
--
-- `(entrenamiento_id, orden_secuencia)` identifica un punto: el
-- orden lo pone la app contando desde 0 y no se repite dentro de
-- un entrenamiento.
--
-- Corre esto DESPUÉS de 0052_foro_retirar_publicacion.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Limpiar lo que impediría crear el índice
--
-- Si algún entrenamiento ya tiene dos puntos con el mismo orden
-- (un reintento a mano, o un insert que entró dos veces), el
-- índice único no se puede crear. Se queda uno de cada grupo, el
-- de `id` menor.
--
-- Los puntos de un mismo orden son el mismo punto enviado dos
-- veces, así que da igual cuál se conserve: tienen las mismas
-- coordenadas y la misma hora de captura. Esto no borra puntos
-- distintos del recorrido.
--
-- El `raise notice` dice cuántos se fueron: si el número no es 0,
-- vale la pena mirar de dónde salieron antes de seguir.
-- -------------------------------------------------------------
do $$
declare
  v_borrados integer;
begin
  with repetidos as (
    select id
    from (
      select id,
             row_number() over (
               partition by entrenamiento_id, orden_secuencia
               order by id
             ) as cual
      from puntos_gps
    ) numerados
    where cual > 1
  ), borrados as (
    delete from puntos_gps
    where id in (select id from repetidos)
    returning 1
  )
  select count(*) into v_borrados from borrados;

  raise notice 'puntos_gps duplicados eliminados: %', v_borrados;
end
$$;

-- -------------------------------------------------------------
-- 2. El índice
--
-- Único, para que la base rechace el duplicado; y sirve además
-- para leer el recorrido de un entrenamiento en orden, que es
-- como lo pide el resumen.
-- -------------------------------------------------------------
create unique index puntos_gps_entrenamiento_orden_idx
  on puntos_gps (entrenamiento_id, orden_secuencia);

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Que el índice está:
--
--   select indexname from pg_indexes
--   where tablename = 'puntos_gps';
--
--   Tiene que aparecer `puntos_gps_entrenamiento_orden_idx`.
--
-- 2. Que no quedó ningún duplicado:
--
--   select entrenamiento_id, orden_secuencia, count(*)
--   from puntos_gps
--   group by 1, 2
--   having count(*) > 1;
--
--   Cero filas.
--
-- 3. Que la base rechaza el duplicado. Con la sesión de un
--    usuario que tenga un entrenamiento con puntos (ver la
--    cabecera de suplantación de 0052):
--
--   insert into puntos_gps
--     (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
--   select entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia
--   from puntos_gps
--   where entrenamiento_id = '<TU ENTRENAMIENTO>'
--   limit 1;
--
--   Falla con 23505 (unique_violation). Ese es el error que la
--   app se ahorra enviando los lotes con `on conflict do nothing`.
--
-- 4. Y que así enviado no falla ni duplica:
--
--   insert into puntos_gps
--     (entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia)
--   select entrenamiento_id, latitud, longitud, capturado_en, orden_secuencia
--   from puntos_gps
--   where entrenamiento_id = '<TU ENTRENAMIENTO>'
--   limit 1
--   on conflict (entrenamiento_id, orden_secuencia) do nothing;
--
--   Dice `INSERT 0 0`: no entró nada y no hubo error. Comprueba
--   que el número de puntos no cambió:
--
--   select count(*) from puntos_gps
--   where entrenamiento_id = '<TU ENTRENAMIENTO>';
-- -------------------------------------------------------------
