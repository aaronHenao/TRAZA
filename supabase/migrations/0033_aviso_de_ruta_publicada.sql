-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-241: avisar que la ruta se publicó
--
-- Criterio 2: cuando la ruta queda publicada, hay que avisarle a
-- su autor.
--
-- El aviso lo dispara el cambio de estado, no quien lo hace. La
-- pantalla con la que el Runner Experto aprueba es de otra
-- historia y todavía no existe; así da igual quién termine
-- aprobando —esa pantalla, el administrador o un `update` a mano
-- desde el SQL Editor—, porque el que avisa es este trigger.
--
-- `after update`: la fila ya quedó como queda, con su
-- `fecha_publicacion` puesta por `rutas_sellar_publicacion`
-- (0029). Y la condición `when` es la que hace que solo avise en
-- la transición: editar cualquier otra cosa de una ruta ya
-- publicada no vuelve a avisar.
--
-- Rechazar una ruta también debería avisarle al autor, con su
-- motivo. No se hace aquí: el rechazo es de la HU de la revisión
-- y lo suyo es que lo añada quien la implemente. El tipo
-- `ruta_rechazada` ya está previsto en 0032.
--
-- Corre esto DESPUÉS de 0032_notificaciones.sql.
-- =============================================================

create function public.avisar_ruta_publicada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `security definer` para poder llamar a `crear_notificacion()`,
  -- que no tiene permiso de ejecución para los usuarios: dentro de
  -- esta función el usuario en curso es su dueño.
  perform public.crear_notificacion(
    new.autor_id,
    'ruta_publicada',
    'Tu ruta ya está publicada',
    format('«%s» ya la puede ver toda la comunidad.', new.nombre),
    new.id
  );

  return null;
end;
$$;

create trigger rutas_avisar_publicacion
  after update on rutas
  for each row
  when (new.estado = 'publicada' and old.estado <> 'publicada')
  execute function public.avisar_ruta_publicada();

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Publica una ruta tuya que esté en revisión:
--
--   update rutas set estado = 'publicada'
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
--   Tiene que decir 'ruta_publicada', traer el nombre de la ruta
--   en el mensaje, apuntar a su id y estar sin leer.
--
-- 2. Y que no avise dos veces por lo mismo:
--
--   update rutas set descripcion = 'otra cosa'
--   where id = '<TU RUTA>';
--
--   No debe aparecer una notificación nueva.
--
-- Para dejar la base limpia:
--
--   delete from notificaciones where entidad_id = '<TU RUTA>';
-- -------------------------------------------------------------
