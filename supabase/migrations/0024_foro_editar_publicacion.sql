-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-355: el autor edita su
-- publicación
--
-- Corre esto DESPUÉS de 0023_foro_publicacion_de_admin.sql.
--
-- El autor cambia el título y el contenido de lo suyo mientras
-- esté publicado. Los límites de 0020 aplican igual al editar.
-- Eliminar la propia publicación todavía no existe (ver
-- docs/deudas.md).
-- =============================================================

-- -------------------------------------------------------------
-- RLS
--
-- Solo lo propio y solo lo publicado: lo retenido espera a la
-- moderación y no se cambia por debajo. Si la fila no cumple,
-- el update no toca nada y la app lo traduce a "ya no se
-- encuentra disponible".
-- -------------------------------------------------------------
create policy "el autor edita lo suyo mientras esté publicado"
  on publicaciones_foro for update
  using (auth.uid() = autor_id and estado = 'publicada')
  with check (auth.uid() = autor_id and estado = 'publicada');

-- -------------------------------------------------------------
-- Editar es cambiar el texto, nada más
--
-- La policy dice qué filas; este trigger dice qué columnas. Sin
-- él, el autor podría mandar otro nombre, otra fecha o quitarse
-- el motivo de moderación. Cuando el administrador modere
-- (SCRUM-322 / SCRUM-242) hay que dejarle cambiar el estado aquí.
-- -------------------------------------------------------------
create function public.proteger_publicacion_foro()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.id := old.id;
  new.autor_id := old.autor_id;
  new.autor_nombre := old.autor_nombre;
  new.autor_es_admin := old.autor_es_admin;
  new.estado := old.estado;
  new.motivo_moderacion := old.motivo_moderacion;
  new.fecha_creacion := old.fecha_creacion;
  return new;
end;
$$;

create trigger publicaciones_foro_proteger
  before update on publicaciones_foro
  for each row execute function public.proteger_publicacion_foro();
