-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-355: historial de
-- versiones de las publicaciones editadas
--
-- Corre esto DESPUÉS de 0024_foro_editar_publicacion.sql.
--
-- Editar ya no borra lo que había: cada vez que cambian el
-- título o el contenido, la versión anterior se guarda aquí y la
-- publicación queda marcada como editada (`fecha_edicion`).
-- Cualquiera que pueda ver la publicación puede ver su historial.
-- =============================================================

-- Null mientras no se haya editado nunca.
alter table publicaciones_foro
  add column fecha_edicion timestamptz;

create table versiones_publicacion_foro (
  id              uuid primary key default gen_random_uuid(),
  publicacion_id  uuid not null references publicaciones_foro(id) on delete cascade,
  titulo          text not null,
  contenido       text not null,
  -- Desde cuándo se leía así: la creación o la edición anterior.
  vigente_desde   timestamptz not null,
  -- Cuándo la reemplazó la edición siguiente.
  reemplazada_en  timestamptz not null default now()
);

create index versiones_publicacion_foro_publicacion_idx
  on versiones_publicacion_foro (publicacion_id, reemplazada_en desc);

-- -------------------------------------------------------------
-- RLS
--
-- El historial se ve si se ve la publicación: la subconsulta
-- pasa por las policies de select de `publicaciones_foro`.
--
-- Nadie escribe aquí desde la app. Lo llena el trigger de abajo,
-- que corre como dueño de la función.
-- -------------------------------------------------------------
alter table versiones_publicacion_foro enable row level security;

create policy "el historial lo ve quien ve la publicación"
  on versiones_publicacion_foro for select
  using (
    exists (
      select 1
      from publicaciones_foro p
      where p.id = publicacion_id
    )
  );

-- -------------------------------------------------------------
-- Editar es cambiar el texto, y lo anterior se guarda
--
-- Reemplaza la función de 0024: además de dejar quietas las
-- columnas que el autor no decide, guarda la versión anterior y
-- marca la fecha de edición. `security definer` para poder
-- escribir en `versiones_publicacion_foro`, que no tiene policy
-- de insert.
-- -------------------------------------------------------------
create or replace function public.proteger_publicacion_foro()
returns trigger
language plpgsql
security definer
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

  if new.titulo is distinct from old.titulo
     or new.contenido is distinct from old.contenido then
    insert into versiones_publicacion_foro
      (publicacion_id, titulo, contenido, vigente_desde)
    values
      (old.id, old.titulo, old.contenido,
       coalesce(old.fecha_edicion, old.fecha_creacion));
    new.fecha_edicion := now();
  else
    new.fecha_edicion := old.fecha_edicion;
  end if;

  return new;
end;
$$;
