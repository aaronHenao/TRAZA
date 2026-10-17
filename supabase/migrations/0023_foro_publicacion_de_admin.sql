-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-354: el administrador
-- publica en el foro
--
-- Corre esto DESPUÉS de 0022_foro_comentario_de_admin.sql.
--
-- El administrador publica desde la moderación y su publicación
-- lleva la insignia "Administrador", igual que sus comentarios.
-- La app no puede leer el rol de otro usuario (`perfiles` solo
-- deja leer el propio), así que la base lo anota en la fila al
-- insertarla, junto con el nombre.
--
-- La policy de insert no cambia: el administrador ya publica a
-- su nombre.
-- =============================================================

alter table publicaciones_foro
  add column autor_es_admin boolean not null default false;

-- Por si el administrador ya había publicado antes de esta migración.
update publicaciones_foro f
   set autor_es_admin = true
  from perfiles p
 where p.id = f.autor_id
   and p.rol = 'admin';

-- -------------------------------------------------------------
-- Lo que el cliente no decide: su nombre, si es administrador,
-- el estado y la hora.
-- -------------------------------------------------------------
create or replace function public.preparar_publicacion_foro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(nullif(btrim(p.nombre), ''), 'Corredor'),
         p.rol = 'admin'
    into new.autor_nombre, new.autor_es_admin
  from perfiles p
  where p.id = new.autor_id;

  -- Sin perfil (no debería pasar: lo crea handle_new_user).
  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');
  new.autor_es_admin := coalesce(new.autor_es_admin, false);
  new.estado := 'publicada';
  new.motivo_moderacion := null;
  new.fecha_creacion := now();
  return new;
end;
$$;
