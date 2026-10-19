-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324: el administrador comenta en el foro
--
-- Corre esto DESPUÉS de 0021_foro_comentarios.sql.
--
-- El administrador también comenta, y su comentario lleva la
-- insignia "Administrador". La app no puede averiguar el rol de otro
-- usuario (`perfiles` solo deja leer el propio), así que la base
-- lo anota en el comentario al insertarlo, igual que el nombre.
--
-- La policy de insert no cambia: el administrador ya comenta a
-- su nombre, y solo lo que está publicado.
-- =============================================================

alter table comentarios_foro
  add column autor_es_admin boolean not null default false;

-- Por si el administrador ya había comentado antes de esta migración.
update comentarios_foro c
   set autor_es_admin = true
  from perfiles p
 where p.id = c.autor_id
   and p.rol = 'admin';

-- -------------------------------------------------------------
-- Lo que el cliente no decide: su nombre, si es administrador y
-- la hora.
-- -------------------------------------------------------------
create or replace function public.preparar_comentario_foro()
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

  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');
  new.autor_es_admin := coalesce(new.autor_es_admin, false);
  new.fecha_creacion := now();
  return new;
end;
$$;
