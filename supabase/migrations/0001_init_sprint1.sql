-- =============================================================
-- TRAZA — Sprint 1: esquema inicial
-- Nota: la entidad Usuario no se crea aquí — Supabase Auth ya
-- gestiona auth.users automáticamente.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1. permisos_usuario
-- -------------------------------------------------------------
create table permisos_usuario (
  id                    uuid primary key default gen_random_uuid(),
  usuario_id            uuid not null references auth.users(id) on delete cascade,
  tipo_permiso          text not null check (tipo_permiso in ('ubicacion', 'salud')),
  concedido             boolean not null default false,
  fecha_actualizacion   timestamptz not null default now(),
  unique (usuario_id, tipo_permiso)
);

alter table permisos_usuario enable row level security;

create policy "usuario gestiona sus propios permisos"
  on permisos_usuario
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 2. objetivos
-- -------------------------------------------------------------
create table objetivos (
  id                uuid primary key default gen_random_uuid(),
  usuario_id        uuid not null references auth.users(id) on delete cascade,
  tipo              text not null check (tipo in ('distancia', 'frecuencia')),
  valor_meta        numeric not null,
  fecha_creacion    timestamptz not null default now()
);

alter table objetivos enable row level security;

create policy "usuario gestiona sus propios objetivos"
  on objetivos
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 3. tipos_actividad (catálogo — solo lectura desde el cliente)
-- -------------------------------------------------------------
create table tipos_actividad (
  id      uuid primary key default gen_random_uuid(),
  nombre  text not null unique
);

alter table tipos_actividad enable row level security;

create policy "cualquier usuario autenticado puede leer el catálogo"
  on tipos_actividad
  for select
  using (auth.role() = 'authenticated');

-- sin política de insert/update/delete → el cliente no puede escribir aquí

insert into tipos_actividad (nombre) values
  ('Correr'),
  ('Trote'),
  ('Caminar');

-- -------------------------------------------------------------
-- 4. entrenamientos
-- -------------------------------------------------------------
create table entrenamientos (
  id                    uuid primary key default gen_random_uuid(),
  usuario_id            uuid not null references auth.users(id) on delete cascade,
  tipo_actividad_id     uuid not null references tipos_actividad(id),
  fecha_inicio          timestamptz not null default now(),
  fecha_fin             timestamptz,
  duracion_segundos     integer,
  distancia_total_m     numeric,
  estado                text not null default 'en_curso'
                        check (estado in ('en_curso', 'finalizado', 'cancelado'))
);

alter table entrenamientos enable row level security;

create policy "usuario gestiona sus propios entrenamientos"
  on entrenamientos
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 5. puntos_gps (SIN altitud, a petición explícita)
-- -------------------------------------------------------------
create table puntos_gps (
  id                  uuid primary key default gen_random_uuid(),
  entrenamiento_id    uuid not null references entrenamientos(id) on delete cascade,
  latitud             double precision not null,
  longitud            double precision not null,
  capturado_en        timestamptz not null default now(),
  orden_secuencia     integer not null
);

alter table puntos_gps enable row level security;

-- puntos_gps no tiene usuario_id propio, así que se valida
-- a través del entrenamiento al que pertenece
create policy "usuario gestiona los puntos de sus propios entrenamientos"
  on puntos_gps
  for all
  using (
    exists (
      select 1 from entrenamientos e
      where e.id = puntos_gps.entrenamiento_id
        and e.usuario_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from entrenamientos e
      where e.id = puntos_gps.entrenamiento_id
        and e.usuario_id = auth.uid()
    )
  );
