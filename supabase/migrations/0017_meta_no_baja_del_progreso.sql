-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-133: la meta no baja de lo ya corrido
--
-- Bajar la meta por debajo de lo que alguien lleva hecho dejaba
-- al corredor en un sitio del que no puede salir: con 10 km de
-- 9, en curso y sin cobrar.
--
-- Nadie reevalúa un reto cuando cambia su meta. Lo único que
-- compara progreso con meta es `otorgar_experiencia()`
-- (0009_experiencia.sql), que solo corre al finalizar un
-- entrenamiento. Así que ese corredor se queda esperando su
-- próxima carrera para que le cuente el reto que ya cumplió, y
-- si no vuelve a correr antes de `fecha_fin` lo pierde.
--
-- Completarlo y pagarlo aquí no se puede: `experiencia_ganada`
-- exige `entrenamiento_id not null` a propósito — toda XP nace
-- de un entrenamiento. Darle salida a eso es de la historia de
-- la XP, no de esta. Lo que sí toca aquí es no crear el agujero.
--
-- Corre esto DESPUÉS de 0016_edicion_retos.sql.
-- =============================================================

-- Se reemplaza la función de 0016 en vez de añadir otro trigger:
-- la pregunta que responde es la misma, "qué cambios de un reto
-- se pueden guardar", y repartirla en dos sitios obliga a
-- buscarla en dos sitios.
--
-- Pasa a `security definer` por la lectura de `retos_usuario`:
-- su RLS deja al administrador ver todas las filas, pero el
-- recuento no debe depender de quién dispare el update. La
-- función no recibe nada del cliente más que `new`, y
-- `search_path` queda fijo.
create or replace function impedir_cambios_que_mueven_el_reto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_llevado numeric;
begin
  if new.periodicidad is distinct from old.periodicidad then
    raise exception 'la periodicidad de un reto no se cambia'
      using errcode = '23514';
  end if;

  if new.tipo_actividad_id is distinct from old.tipo_actividad_id then
    raise exception 'el tipo de actividad de un reto no se cambia'
      using errcode = '23514';
  end if;

  if new.fecha_inicio is distinct from old.fecha_inicio then
    raise exception 'la fecha de inicio de un reto no se cambia'
      using errcode = '23514';
  end if;

  if new.fecha_fin < old.fecha_fin then
    raise exception 'la fecha de fin solo se puede extender'
      using errcode = '23514';
  end if;

  -- Solo al bajarla: subir la meta no deja a nadie pasado, y así
  -- la consulta no se paga en cada edición.
  if new.meta_km < old.meta_km then
    -- Solo los que siguen en progreso. A quien ya lo completó no
    -- le quita nada que la meta baje, y lo vencido es historia.
    --
    -- Sin filtrar por fecha a propósito: la base corre en UTC y
    -- aquí no se sabe qué día es en el teléfono de nadie (de ahí
    -- que ningún trigger de retos mire `current_date`). Contar
    -- también los de un reto ya caducado deja la regla más
    -- estricta de lo necesario, que es el lado correcto para
    -- equivocarse.
    select max(progreso_km) into v_llevado
    from retos_usuario
    where reto_id = old.id
      and estado = 'en_progreso';

    -- Redondeado a los dos decimales con los que la app pinta los
    -- km: el progreso viene del GPS y trae más precisión de la que
    -- se ve. Comparar entero haría que la app rechazara el mismo
    -- número que acaba de sugerir en pantalla.
    if v_llevado is not null and new.meta_km < round(v_llevado, 2) then
      raise exception
        'hay un corredor con % km hechos: la meta no puede bajar de ahi',
        round(v_llevado, 2)
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

-- El trigger `retos_cambios_permitidos` de 0016 sigue en pie y
-- apunta a esta función: no hace falta recrearlo.
