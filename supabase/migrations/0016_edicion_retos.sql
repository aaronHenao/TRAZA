-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-133: edición de retos
--
-- El administrador puede corregir un reto ya publicado, pero no
-- todo: lo que cambiaría de sitio a quien ya lo está haciendo
-- queda fijo.
--
-- Corre esto DESPUÉS de 0015_reto_tipo_actividad.sql.
-- =============================================================

-- -------------------------------------------------------------
-- Lo que no se puede cambiar de un reto ya creado
-- -------------------------------------------------------------
-- La policy de update (0006_retos.sql) ya decide *quién* puede
-- editar. Esto decide *qué*, que es otra cosa: el administrador
-- tiene permiso, pero hay cambios que dejarían datos que no se
-- pueden sostener.
--
--   periodicidad y tipo_actividad_id
--     Juntos forman el hueco que ocupa un reto. Cambiar
--     cualquiera de los dos movería de hueco a quien ya lo tiene
--     activo, y podría dejarlo con dos retos del mismo — justo
--     lo que impide el trigger de 0015, colado por la puerta de
--     atrás: aquel mira los insert en retos_usuario, no los
--     update en retos.
--
--   fecha_inicio
--     No se escribe, se calcula a partir de la periodicidad
--     (SCRUM-142). Moverla dejaría una vigencia que no concuerda
--     con el período que dice tener.
--
--   fecha_fin solo hacia adelante
--     Alargar el plazo no le quita nada a nadie. Acortarlo
--     dejaría fuera a quien iba cumpliendo el reto, sin haber
--     hecho nada mal.
--
-- La pantalla ya no ofrece ninguno de estos cambios; esto es
-- para que la regla valga también para quien llame a la API por
-- su cuenta, que con la publishable key es cualquiera.
create or replace function impedir_cambios_que_mueven_el_reto()
returns trigger
language plpgsql
as $$
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

  return new;
end;
$$;

create trigger retos_cambios_permitidos
  before update on retos
  for each row
  execute function impedir_cambios_que_mueven_el_reto();
