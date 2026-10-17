-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-323 / SCRUM-341: publicaciones del foro
--
-- Corre esto DESPUÉS de 0005_rol_administrador.sql (es_admin()).
--
-- Cada publicación nace `publicada`. La moderación de la IA
-- (criterio 3 de SCRUM-323, SCRUM-322) todavía no existe: cuando
-- llegue, será ella la que pase una publicación a `retenida` y
-- deje el motivo en `motivo_moderacion`. La tabla y la app ya
-- saben qué hacer con ese estado.
-- =============================================================

create table publicaciones_foro (
  id                 uuid primary key default gen_random_uuid(),
  autor_id           uuid not null references auth.users(id) on delete cascade,
  -- Copia del nombre al publicar. `perfiles` solo deja leer el
  -- perfil propio, así que sin esta columna nadie vería quién
  -- escribió las publicaciones de los demás. La pone el trigger.
  autor_nombre       text not null,
  titulo             text not null,
  contenido          text not null,
  estado             text not null default 'publicada',
  motivo_moderacion  text,
  fecha_creacion     timestamptz not null default now()
);

-- Los límites son los mismos de `BorradorPublicacion` en Dart.
alter table publicaciones_foro
  add constraint publicaciones_foro_titulo_valido
    check (length(btrim(titulo)) between 1 and 120),
  add constraint publicaciones_foro_contenido_valido
    check (length(btrim(contenido)) between 1 and 2000),
  add constraint publicaciones_foro_estado_valido
    check (estado in ('publicada', 'retenida', 'eliminada'));

-- El foro lista lo publicado, de lo más reciente a lo más antiguo.
create index publicaciones_foro_estado_fecha_idx
  on publicaciones_foro (estado, fecha_creacion desc);

-- -------------------------------------------------------------
-- Lo que el cliente no decide
--
-- El nombre del autor sale de su perfil y el estado lo pone la
-- base: si el cliente pudiera mandarlo, cualquiera publicaría con
-- otro nombre o se saltaría la moderación que venga después.
-- -------------------------------------------------------------
create function public.preparar_publicacion_foro()
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

  -- Sin perfil (no debería pasar: lo crea handle_new_user).
  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');
  new.estado := 'publicada';
  new.motivo_moderacion := null;
  new.fecha_creacion := now();
  return new;
end;
$$;

create trigger publicaciones_foro_preparar
  before insert on publicaciones_foro
  for each row execute function public.preparar_publicacion_foro();

-- -------------------------------------------------------------
-- RLS
--
-- Lo publicado lo ve cualquier usuario con sesión. El autor ve
-- además lo suyo aunque quede retenido, y el administrador lo ve
-- todo para moderarlo.
--
-- Sin policies de update ni de delete, a propósito: aprobar,
-- retener y eliminar llegan con SCRUM-322 y SCRUM-242.
-- -------------------------------------------------------------
alter table publicaciones_foro enable row level security;

create policy "lo publicado lo lee cualquier usuario autenticado"
  on publicaciones_foro for select
  using (auth.role() = 'authenticated' and estado = 'publicada');

create policy "el autor ve sus propias publicaciones"
  on publicaciones_foro for select
  using (auth.uid() = autor_id);

create policy "el administrador ve todas las publicaciones"
  on publicaciones_foro for select
  using (public.es_admin());

create policy "el usuario publica a su nombre"
  on publicaciones_foro for insert
  with check (auth.uid() = autor_id);
