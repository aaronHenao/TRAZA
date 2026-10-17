-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-241: las notificaciones en vivo
--
-- Un aviso llega justo cuando el usuario no lo está pidiendo: el
-- Runner Experto aprueba la ruta mientras él mira otra cosa. Sin
-- esto la campana solo se entera al volver a la portada o al
-- tirar para refrescar, que es lo que hace hoy.
--
-- Se publica `notificaciones` en Supabase Realtime, como ya hace
-- 0028 con el foro. La app no pinta lo que llega: lo toma como
-- aviso y vuelve a consultar, así que lo que ve cada usuario
-- sigue saliendo de la misma consulta y pasando por las policies
-- de select.
--
-- Aquí eso importa más que en el foro: una notificación es
-- personal. Realtime reparte cada evento solo a quien la policy
-- de select deja ver la fila —"cada uno ve sus notificaciones"
-- (0032)—, así que a nadie le llegan los avisos de otro. Además
-- la app se suscribe filtrando por su propio `usuario_id`: la
-- barrera es la policy, pero no cuesta nada no pedir lo ajeno.
--
-- Corre esto DESPUÉS de 0032_notificaciones.sql.
-- =============================================================

alter publication supabase_realtime
  add table notificaciones;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
--   select tablename
--   from pg_publication_tables
--   where pubname = 'supabase_realtime'
--   order by tablename;
--
-- Tiene que aparecer `notificaciones` junto a las del foro.
-- -------------------------------------------------------------
