-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-331: avisar que la ruta se rechazó
--
-- Criterios 3 y 5 de SCRUM-321: cuando el administrador o el
-- Runner Experto rechaza una ruta, hay que avisarle a su autor
-- con el motivo.
--
-- Es el gemelo de `avisar_ruta_publicada()` (0033): el aviso lo
-- dispara el cambio de estado, no quien lo hace. Así da igual si
-- rechaza el administrador, el experto o un `update` a mano
-- desde el SQL Editor. El tipo `ruta_rechazada` ya estaba
-- previsto en 0032.
--
-- `old.estado` dice quién la rechazó: si estaba `en_revision`
-- fue el administrador, si estaba `revision_experto` fue el
-- experto. El mensaje lo cuenta, porque al autor le sirve saber
-- en qué etapa se quedó.
--
-- Cabe en los 500 caracteres de `notificaciones_mensaje_valido`:
-- el nombre de la ruta tiene hasta 120 (0029) y el motivo hasta
-- 300 (0043).
--
-- Se escribió como 0037 y ya está aplicada en la base compartida
-- (ver la cabecera de 0043): ahí NO hay que volver a correrla.
--
-- Corre esto DESPUÉS de 0043_revision_de_rutas.sql.
-- =============================================================

create function public.avisar_ruta_rechazada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quien text := case old.estado
    when 'revision_experto' then 'un Runner Experto'
    else 'el administrador'
  end;
begin
  -- `security definer` por lo mismo que en 0033: `crear_notificacion()`
  -- no tiene permiso de ejecución para los usuarios.
  perform public.crear_notificacion(
    new.autor_id,
    'ruta_rechazada',
    'Tu ruta no fue publicada',
    format(
      '«%s» fue rechazada por %s. Motivo: %s',
      new.nombre,
      v_quien,
      coalesce(new.motivo_rechazo, 'sin motivo')
    ),
    new.id
  );

  return null;
end;
$$;

create trigger rutas_avisar_rechazo
  after update on rutas
  for each row
  when (new.estado = 'rechazada' and old.estado <> 'rechazada')
  execute function public.avisar_ruta_rechazada();

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Rechaza una ruta tuya que esté en revisión:
--
--   update rutas
--      set estado = 'rechazada', motivo_rechazo = 'Cruza una autopista'
--   where id = '<TU RUTA>';
--
--   Y mira qué llegó:
--
--   select tipo, titulo, mensaje, entidad_id, leida_en
--   from notificaciones
--   where usuario_id = '<TU USUARIO>'
--   order by fecha_creacion desc
--   limit 1;
--
--   Tiene que decir 'ruta_rechazada', "fue rechazada por el
--   administrador", traer el motivo, apuntar a la ruta y estar
--   sin leer.
--
-- 2. Y que no avise dos veces por lo mismo:
--
--   update rutas set descripcion = 'otra cosa' where id = '<TU RUTA>';
--
--   No debe aparecer una notificación nueva.
--
-- Para dejar la base limpia:
--
--   delete from notificaciones where entidad_id = '<TU RUTA>';
--   update rutas set estado = 'en_revision', motivo_rechazo = null
--   where id = '<TU RUTA>';
-- -------------------------------------------------------------
