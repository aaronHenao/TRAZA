-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-324 / SCRUM-356: el autor edita sus
-- comentarios y el administrador audita los cambios
--
-- Corre esto DESPUÉS de 0026_foro_historial_solo_admin.sql.
--
-- Igual que con las publicaciones (0024 a 0026): el autor cambia
-- el texto de lo suyo mientras la publicación siga publicada,
-- todos ven que se editó (`fecha_edicion`) y lo que decía antes
-- solo lo lee el administrador.
-- =============================================================

-- Null mientras no se haya editado nunca.
alter table comentarios_foro
  add column fecha_edicion timestamptz;

create table versiones_comentario_foro (
  id              uuid primary key default gen_random_uuid(),
  comentario_id   uuid not null references comentarios_foro(id) on delete cascade,
  contenido       text not null,
  -- Desde cuándo se leía así: la creación o la edición anterior.
  vigente_desde   timestamptz not null,
  -- Cuándo la reemplazó la edición siguiente.
  reemplazada_en  timestamptz not null default now()
);

create index versiones_comentario_foro_comentario_idx
  on versiones_comentario_foro (comentario_id, reemplazada_en desc);

-- -------------------------------------------------------------
-- RLS
--
-- El historial es para auditar: solo el administrador lo lee.
-- Nadie escribe aquí desde la app; lo llena el trigger de abajo.
--
-- Editar exige que el comentario sea propio y que la publicación
-- siga publicada, la misma regla que para comentar (criterio 3
-- de SCRUM-324).
-- -------------------------------------------------------------
alter table versiones_comentario_foro enable row level security;

create policy "el administrador ve el historial de los comentarios"
  on versiones_comentario_foro for select
  using (public.es_admin());

create policy "el autor edita su comentario mientras la publicación esté publicada"
  on comentarios_foro for update
  using (
    auth.uid() = autor_id
    and exists (
      select 1
      from publicaciones_foro p
      where p.id = publicacion_id
        and p.estado = 'publicada'
    )
  )
  with check (auth.uid() = autor_id);

-- -------------------------------------------------------------
-- Editar es cambiar el texto, y lo anterior se guarda
--
-- La policy dice qué filas; el trigger, qué columnas. Lo que no
-- es el contenido queda como estaba. `security definer` para
-- escribir en `versiones_comentario_foro`, que no tiene policy
-- de insert.
-- -------------------------------------------------------------
create function public.proteger_comentario_foro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.id := old.id;
  new.publicacion_id := old.publicacion_id;
  new.autor_id := old.autor_id;
  new.autor_nombre := old.autor_nombre;
  new.autor_es_admin := old.autor_es_admin;
  new.fecha_creacion := old.fecha_creacion;

  if new.contenido is distinct from old.contenido then
    insert into versiones_comentario_foro
      (comentario_id, contenido, vigente_desde)
    values
      (old.id, old.contenido, coalesce(old.fecha_edicion, old.fecha_creacion));
    new.fecha_edicion := now();
  else
    new.fecha_edicion := old.fecha_edicion;
  end if;

  return new;
end;
$$;

create trigger comentarios_foro_proteger
  before update on comentarios_foro
  for each row execute function public.proteger_comentario_foro();
