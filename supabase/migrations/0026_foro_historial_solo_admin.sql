-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-355: el historial de
-- versiones solo lo ve el administrador
--
-- Corre esto DESPUÉS de 0025_foro_historial_de_versiones.sql.
--
-- Todos siguen viendo que una publicación fue editada
-- (`publicaciones_foro.fecha_edicion`), pero lo que decía antes
-- es para moderar, no para el foro.
-- =============================================================

drop policy "el historial lo ve quien ve la publicación"
  on versiones_publicacion_foro;

create policy "el administrador ve el historial de versiones"
  on versiones_publicacion_foro for select
  using (public.es_admin());
