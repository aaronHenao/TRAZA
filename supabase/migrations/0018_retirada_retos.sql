-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-134: retirada de retos
--
-- Retirar un reto es cambiarle el estado a 'retirado', como ya
-- previó 0006_retos.sql al dejar la tabla sin policy de delete:
-- la fila se queda para que el historial y la XP de los
-- corredores sigan teniendo a qué apuntar.
--
-- Esta migración añade las dos cosas que la baja lógica necesita
-- y que todavía no estaban:
--
--   1. Que el corredor siga viendo el reto que alcanzó a activar
--      aunque se retire, o su historial se queda sin la mitad de
--      los datos.
--   2. Que no se pueda retirar un reto que alguien todavía puede
--      terminar.
--
-- Corre esto DESPUÉS de 0017_meta_no_baja_del_progreso.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. El historial sobrevive a la retirada (SCRUM-160)
-- -------------------------------------------------------------
-- La policy de 0006 deja al corredor ver solo los retos
-- 'activo'. En cuanto uno se retira, `misRetos()` —que embebe
-- `retos(...)` en la consulta de `retos_usuario`— recibe el reto
-- en nulo, y una fila de progreso sin su meta y su vigencia no
-- significa nada: la pantalla de historial se queda sin poder
-- leer ni lo que el corredor cumplió.
--
-- Esto no devuelve los retirados al catálogo: `vigentes()` y
-- `caducados()` filtran por estado en la consulta. RLS decide
-- quién puede ver qué, y lo que cada pantalla muestra lo decide
-- su consulta.
--
-- Las policies de select se suman (OR), así que esta amplía la
-- de 0006 sin reemplazarla: solo alcanza a los retos que ese
-- mismo corredor tiene en `retos_usuario`.
create policy "el corredor ve los retos retirados que ya habia activado"
  on retos
  for select
  using (
    exists (
      select 1
      from retos_usuario ru
      where ru.reto_id = retos.id
        and ru.usuario_id = auth.uid()
    )
  );

-- -------------------------------------------------------------
-- 2. No se retira lo que alguien todavía puede terminar
--    (SCRUM-159)
-- -------------------------------------------------------------
-- Se reemplaza otra vez la función de 0016/0017: sigue siendo la
-- misma pregunta, qué cambios de un reto se pueden guardar.
--
-- La regla de la historia es que un reto se retira cuando ya no
-- hay nada en juego: o no lo tiene nadie en curso, o a quien lo
-- tiene ya se le pasó el plazo y no lo cumplió. Quitarle a
-- alguien un reto que todavía puede cerrar sería quitarle la XP
-- que está a punto de ganar.
--
-- Para eso hay que saber qué día es, y la base corre en UTC.
-- Se usa la hora de Colombia, como ya hace 0009_experiencia.sql
-- para decidir a qué día cuenta la XP de un entrenamiento: entre
-- las 19:00 y la medianoche, `current_date` en UTC ya es mañana
-- y el reto parecería caducado medio día antes de serlo.
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
    -- Sin filtrar por fecha a propósito: contar también los de
    -- un reto ya caducado deja la regla más estricta de lo
    -- necesario, que es el lado correcto para equivocarse.
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

  -- Retirar: solo cuando ya no hay nada en juego.
  --
  -- Basta con mirar el plazo del reto, no el de cada corredor:
  -- si sigue vigente, cualquiera que lo tenga en curso puede
  -- cerrarlo hoy mismo.
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
-- Lo que NO hace esta migración
-- -------------------------------------------------------------
-- No toca las filas de `retos_usuario` al retirar. No hace
-- falta y sería peor:
--
--   · Dejar de sumar ya está resuelto. El trigger de
--     0009_experiencia.sql solo avanza retos con
--     `r.estado = 'activo'`, así que un reto retirado no vuelve
--     a moverse por sí solo.
--   · A quien lo tenga en curso ya se le pasó el plazo (eso es
--     lo que comprueba la regla de arriba), así que la app lo
--     pinta vencido como cualquier otro reto que no se cumplió.
--   · El progreso es del corredor. Quien lo escribe es el
--     trigger de la XP, y nadie más debería.
