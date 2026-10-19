-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-357: el foro en tiempo real
--
-- Corre esto DESPUÉS de 0027_foro_editar_comentarios.sql.
--
-- Publica los cambios de las publicaciones y los comentarios en
-- Supabase Realtime (Postgres Changes). La app no pinta lo que
-- llega: lo toma como aviso y vuelve a consultar, así que lo que
-- ve cada usuario sigue pasando por las policies de select.
-- Realtime además respeta esas mismas policies al repartir los
-- eventos: lo retenido no le llega a quien no lo puede ver.
--
-- Las tablas de historial (`versiones_*`) no se publican: son
-- para auditar, no para el foro.
-- =============================================================

alter publication supabase_realtime
  add table publicaciones_foro, comentarios_foro;
