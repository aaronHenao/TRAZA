-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-138: catálogo de retos
--
-- Los retos los crea y mantiene el administrador; los corredores
-- solo los leen. La relación usuario–reto (activar un reto,
-- llevar su progreso) NO se define aquí: es de SCRUM-136 y va en
-- su propia migración.
--
-- Corre esto DESPUÉS de 0005_rol_administrador.sql, que trae la
-- función es_admin() de la que dependen las policies.
-- =============================================================

create table retos (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  descripcion     text not null,
  periodicidad    text not null,
  meta_km         numeric not null,
  xp_otorgada     integer not null,
  fecha_inicio    date not null,
  fecha_fin       date not null,
  -- SCRUM-145: todo reto nace activo. El estado lo pone el
  -- default, no el cliente.
  estado          text not null default 'activo',
  -- Auditoría. `set null` y no `cascade`: si algún día se borra
  -- la cuenta del administrador, el reto y su historial siguen.
  creado_por      uuid references auth.users(id) on delete set null,
  fecha_creacion  timestamptz not null default now()
);

-- -------------------------------------------------------------
-- Restricciones
--
-- Con nombre y por separado para que el error diga cuál falló.
-- Las mismas reglas se validan antes en Dart (SCRUM-141 y 144),
-- pero aquí son la última palabra: el cliente habla directo con
-- Postgres, así que lo que no esté en la tabla no está validado.
-- -------------------------------------------------------------
alter table retos
  add constraint retos_periodicidad_valida
    check (periodicidad in ('diaria', 'semanal', 'mensual')),

  add constraint retos_estado_valido
    check (estado in ('activo', 'retirado')),

  -- Criterio 2 de SCRUM-132: meta y XP mayores que cero.
  add constraint retos_meta_positiva
    check (meta_km > 0),

  add constraint retos_xp_positiva
    check (xp_otorgada > 0),

  -- "Obligatorio" es tener contenido, no solo estar presente:
  -- una cadena de espacios no es un nombre.
  add constraint retos_nombre_no_vacio
    check (length(btrim(nombre)) > 0),

  add constraint retos_descripcion_no_vacia
    check (length(btrim(descripcion)) > 0),

  -- La vigencia la calcula el servicio según la periodicidad
  -- (SCRUM-142); aquí solo se comprueba que no esté invertida.
  add constraint retos_vigencia_coherente
    check (fecha_fin >= fecha_inicio);

-- -------------------------------------------------------------
-- Índice del catálogo
--
-- Las dos consultas que van a existir filtran por estado y
-- ordenan o recortan por vigencia: la del administrador
-- (activos / retirados) y la de los corredores (vigentes hoy).
-- -------------------------------------------------------------
create index retos_estado_vigencia_idx
  on retos (estado, fecha_fin desc);

-- -------------------------------------------------------------
-- RLS
-- -------------------------------------------------------------
alter table retos enable row level security;

-- Lectura: los corredores ven el catálogo publicado; el
-- administrador ve también los retirados, que necesita para su
-- pantalla de gestión.
--
-- El filtro por vigencia (qué está vigente hoy) NO va aquí: es
-- de la consulta, porque hay pantallas que sí muestran retos
-- vencidos al usuario (SCRUM-173). RLS decide qué puede ver
-- cada quien, no qué se muestra en cada pantalla.
create policy "retos activos visibles para todos, retirados solo para el admin"
  on retos
  for select
  using (
    (auth.role() = 'authenticated' and estado = 'activo')
    or public.es_admin()
  );

-- Escritura: solo el administrador.
--
-- Esta es la barrera de verdad. La app decide qué pantallas
-- muestra según perfiles.rol, pero eso es presentación: con la
-- publishable key cualquiera puede llamar a la API, así que si
-- la única comprobación estuviera en Dart no habría ninguna.
create policy "solo el administrador crea retos"
  on retos
  for insert
  with check (public.es_admin());

create policy "solo el administrador edita retos"
  on retos
  for update
  using (public.es_admin())
  with check (public.es_admin());

-- Sin policy de delete, a propósito: nadie puede borrar una
-- fila de retos. Retirar un reto es cambiar su estado a
-- 'retirado' (SCRUM-157), para que el historial y la XP que ya
-- recibieron los corredores sigan teniendo a qué apuntar.
