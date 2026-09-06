-- =============================================================
-- TRAZA — Sprint 1: tabla de perfiles (extensión de auth.users)
-- Corre esto DESPUÉS de 0001_init_sprint1.sql
-- =============================================================

-- -------------------------------------------------------------
-- 1. Tabla perfiles (1 a 1 con auth.users)
-- -------------------------------------------------------------
create table perfiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  nombre          text,
  auth_provider   text,
  fecha_registro  timestamptz not null default now(),
  activo          boolean not null default true
);

alter table perfiles enable row level security;

create policy "usuario ve y edita su propio perfil"
  on perfiles
  for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- -------------------------------------------------------------
-- 2. Trigger: crea el perfil automáticamente cada vez que
--    Supabase Auth registra un usuario nuevo (correo o Google)
-- -------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.perfiles (id, nombre, auth_provider)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    coalesce(new.raw_app_meta_data->>'provider', 'email')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -------------------------------------------------------------
-- 3. Backfill: si ya registraste usuarios de prueba ANTES de
--    correr este script, esto les crea el perfil que se
--    perdieron (no hace nada si no hay ninguno pendiente)
-- -------------------------------------------------------------
insert into public.perfiles (id, nombre, auth_provider)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'),
  coalesce(u.raw_app_meta_data->>'provider', 'email')
from auth.users u
left join public.perfiles p on p.id = u.id
where p.id is null;
