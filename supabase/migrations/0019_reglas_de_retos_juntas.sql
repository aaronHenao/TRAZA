-- =============================================================
-- TRAZA — Sprint 2: las reglas de un reto, en una sola función
--
-- Dos migraciones salieron con el número 0018 y las dos hacen
-- `create or replace` de `impedir_cambios_que_mueven_el_reto()`:
--
--   0018_retirada_retos.sql    (SCRUM-134) añadió la regla de la
--                              retirada sobre la versión de 0017.
--   0018_xp_solo_por_retos.sql (SCRUM-192) cambió la regla de la
--                              meta, también sobre la de 0017.
--
-- Ninguna de las dos sabía de la otra, así que la que se corriera
-- la última se llevaba por delante la regla de la primera. En la
-- base compartida quedó viva solo una, y cuál depende del orden
-- en que se aplicaran.
--
-- Esta deja la función con las dos reglas, así que sirve de
-- arreglo sin importar en qué orden corrieran. Después de esta,
-- las dos están garantizadas.
--
-- Corre esto DESPUÉS de las dos 0018.
--
-- Para la próxima: una función que vive en varias migraciones se
-- reemplaza entera cada vez, así que quien la toque tiene que
-- partir de la última versión, no de la que recuerde.
-- =============================================================

-- -------------------------------------------------------------
-- Lo que no se puede cambiar de un reto ya creado
--
-- La policy de update (0006) decide *quién* puede editar. Esto
-- decide *qué*, que es otra cosa: el administrador tiene permiso,
-- pero hay cambios que dejarían datos que no se pueden sostener.
--
--   periodicidad y tipo_actividad_id
--     Juntos forman el hueco que ocupa un reto. Moverlo dejaría
--     a quien lo tenga activo con dos retos del mismo hueco, que
--     es lo que impide el trigger de 0015 por la puerta de atrás.
--
--   fecha_inicio
--     No se escribe, se calcula a partir de la periodicidad
--     (SCRUM-142).
--
--   fecha_fin solo hacia adelante
--     Alargar el plazo no le quita nada a nadie. Acortarlo
--     dejaría fuera a quien iba cumpliendo.
--
--   meta_km por encima de lo ya corrido (SCRUM-192)
--     Tal como la dejó 0018_xp_solo_por_retos. Se compara con el
--     progreso real, sin redondear: cualquier meta que no lo
--     supere deja el reto cumplido y sin cobrar, porque lo único
--     que marca un reto como completado es el cierre de un
--     entrenamiento posterior.
--
--   retirar solo cuando no hay nada en juego (SCRUM-159)
--     Tal como la dejó 0018_retirada_retos.
-- -------------------------------------------------------------
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
    -- Sin filtrar por fecha: la base corre en UTC y no sabe qué
    -- día es en el teléfono de nadie. Contar también los de un
    -- reto caducado deja la regla más estricta de lo necesario,
    -- que es el lado correcto para equivocarse.
    select max(progreso_km) into v_llevado
    from retos_usuario
    where reto_id = old.id
      and estado = 'en_progreso';

    -- El mensaje lo muestra redondeado, como lo pinta la app; por
    -- eso dice "por encima": que rechace el mismo número que se ve
    -- es lo correcto.
    if v_llevado is not null and new.meta_km <= v_llevado then
      raise exception
        'hay un corredor con % km hechos: la meta tiene que quedar por encima',
        round(v_llevado, 2)
        using errcode = '23514';
    end if;
  end if;

  -- Retirar: solo cuando ya no hay nada en juego.
  --
  -- Basta con mirar el plazo del reto, no el de cada corredor:
  -- si sigue vigente, cualquiera que lo tenga en curso puede
  -- cerrarlo hoy mismo y retirarlo le quitaría la XP que está a
  -- punto de ganar.
  --
  -- En hora de Colombia, como 0009 para el tope diario de XP: en
  -- UTC, entre las 19:00 y la medianoche el reto parecería
  -- caducado medio día antes de serlo.
  if new.estado = 'retirado' and old.estado <> 'retirado' then
    if old.fecha_fin >= (now() at time zone 'America/Bogota')::date
       and exists (
         select 1
         from retos_usuario
         where reto_id = old.id
           and estado = 'en_progreso'
       ) then
      raise exception
        'hay corredores que todavia pueden completar este reto'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

-- El trigger `retos_cambios_permitidos` de 0016 sigue apuntando
-- a esta función: no hace falta recrearlo.

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
--   select prosrc like '%retirado%'     as regla_de_retirada,
--          prosrc like '%<= v_llevado%' as regla_de_la_meta
--   from pg_proc
--   where proname = 'impedir_cambios_que_mueven_el_reto';
--
-- Las dos tienen que dar `true`.
-- -------------------------------------------------------------
