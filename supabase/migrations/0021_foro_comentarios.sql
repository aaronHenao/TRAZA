-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-349: comentarios del foro
--
-- Corre esto DESPUÉS de 0020_foro_publicaciones.sql.
--
-- Solo se comenta lo que está publicado. Si la publicación fue
-- retenida por la moderación o eliminada, la base rechaza el
-- comentario aunque la app tenga en pantalla una versión vieja
-- (criterio 3 de SCRUM-324).
-- =============================================================

create table comentarios_foro (
  id              uuid primary key default gen_random_uuid(),
  publicacion_id  uuid not null references publicaciones_foro(id) on delete cascade,
  autor_id        uuid not null references auth.users(id) on delete cascade,
  -- Copia del nombre al comentar, por la misma razón que en
  -- publicaciones_foro: `perfiles` solo deja leer el propio.
  autor_nombre    text not null,
  contenido       text not null,
  fecha_creacion  timestamptz not null default now()
);

-- El límite es el mismo de `BorradorComentario` en Dart.
alter table comentarios_foro
  add constraint comentarios_foro_contenido_valido
    check (length(btrim(contenido)) between 1 and 500);

-- Los comentarios se leen por publicación, en el orden en que llegaron.
create index comentarios_foro_publicacion_fecha_idx
  on comentarios_foro (publicacion_id, fecha_creacion);

-- -------------------------------------------------------------
-- Lo que el cliente no decide: su nombre y la hora.
-- -------------------------------------------------------------
create function public.preparar_comentario_foro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(nullif(btrim(p.nombre), ''), 'Corredor')
    into new.autor_nombre
  from perfiles p
  where p.id = new.autor_id;

  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');
  new.fecha_creacion := now();
  return new;
end;
$$;

create trigger comentarios_foro_preparar
  before insert on comentarios_foro
  for each row execute function public.preparar_comentario_foro();

-- -------------------------------------------------------------
-- RLS
--
-- Los comentarios se ven mientras su publicación esté publicada;
-- el administrador los ve siempre, para moderar.
--
-- Comentar exige que la publicación esté publicada en el momento
-- del insert. Si no, Postgres responde 42501 y la app lo traduce
-- a "la publicación ya no se encuentra disponible".
--
-- Sin update ni delete, a propósito.
-- -------------------------------------------------------------
alter table comentarios_foro enable row level security;

create policy "los comentarios de lo publicado los lee cualquier usuario autenticado"
  on comentarios_foro for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1
      from publicaciones_foro p
      where p.id = publicacion_id
        and p.estado = 'publicada'
    )
  );

create policy "el administrador ve todos los comentarios"
  on comentarios_foro for select
  using (public.es_admin());

create policy "el usuario comenta a su nombre lo que está publicado"
  on comentarios_foro for insert
  with check (
    auth.uid() = autor_id
    and exists (
      select 1
      from publicaciones_foro p
      where p.id = publicacion_id
        and p.estado = 'publicada'
    )
  );
