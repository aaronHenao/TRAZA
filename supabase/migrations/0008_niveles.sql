-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-179: niveles de progresión
--
-- Los niveles los crea y mantiene el administrador; los
-- corredores solo los leen: su progresión (SCRUM-178) y la
-- subida automática de nivel (SCRUM-191) necesitan los umbrales.
--
-- Corre esto DESPUÉS de 0005_rol_administrador.sql, que trae la
-- función es_admin() de la que dependen las policies.
-- =============================================================

create table niveles (
  id                  uuid primary key default gen_random_uuid(),
  nombre              text not null,
  -- Experiencia acumulada con la que se entra al nivel. Un nivel
  -- va desde su umbral hasta el del siguiente, así que dos
  -- niveles con el mismo umbral ocuparían el mismo tramo: eso es
  -- el solapamiento que prohíbe SCRUM-177.
  umbral_experiencia  integer not null,
  -- Auditoría, igual que en retos. `set null` y no `cascade`: si
  -- algún día se borra la cuenta del administrador, el nivel y la
  -- progresión que ya alcanzaron los corredores siguen.
  creado_por          uuid references auth.users(id) on delete set null,
  fecha_creacion      timestamptz not null default now()
);

-- -------------------------------------------------------------
-- Restricciones
--
-- Con nombre y por separado para que el error diga cuál falló.
-- Las mismas reglas se validan antes en Dart (SCRUM-181), pero
-- aquí son la última palabra: el cliente habla directo con
-- Postgres, así que lo que no esté en la tabla no está validado.
-- -------------------------------------------------------------
alter table niveles
  -- Criterio 2 de SCRUM-177: el umbral tiene que ser mayor que cero.
  add constraint niveles_umbral_positivo
    check (umbral_experiencia > 0),

  -- "Obligatorio" es tener contenido, no solo estar presente:
  -- una cadena de espacios no es un nombre.
  add constraint niveles_nombre_no_vacio
    check (length(btrim(nombre)) > 0),

  -- Criterio 3: sin solapamiento. Con un umbral por nivel, que no
  -- se solapen es que no se repitan.
  add constraint niveles_umbral_unico
    unique (umbral_experiencia);

-- Nombre único sin distinguir mayúsculas ni espacios de sobra:
-- "Bronce", "bronce" y " Bronce " son el mismo nivel para quien
-- lo lee, y tenerlos repetidos no ayudaría a nadie.
create unique index niveles_nombre_unico_idx
  on niveles (lower(btrim(nombre)));

-- El listado se muestra siempre ordenado por umbral de menor a
-- mayor (criterio 1). No hace falta un índice aparte para eso: la
-- restricción `niveles_umbral_unico` ya crea el suyo sobre esa
-- misma columna.

-- -------------------------------------------------------------
-- RLS
-- -------------------------------------------------------------
alter table niveles enable row level security;

-- Lectura: cualquier cuenta con sesión. La progresión del
-- corredor (SCRUM-178) necesita los umbrales para saber en qué
-- nivel está y cuánta experiencia le falta para el siguiente.
create policy "los niveles los lee cualquier usuario autenticado"
  on niveles
  for select
  using (auth.role() = 'authenticated');

-- Escritura: solo el administrador.
--
-- Esta es la barrera de verdad del criterio de acceso restringido.
-- La app decide qué pantallas muestra según `perfiles.rol`, pero
-- eso es presentación: con la publishable key cualquiera puede
-- llamar a la API, así que si la única comprobación estuviera en
-- Dart no habría ninguna.
create policy "solo el administrador crea niveles"
  on niveles
  for insert
  with check (public.es_admin());

create policy "solo el administrador edita niveles"
  on niveles
  for update
  using (public.es_admin())
  with check (public.es_admin());

-- Sin policy de delete, a propósito: borrar un nivel dejaría sin
-- referencia la progresión que los corredores ya alcanzaron. Si
-- más adelante hace falta retirarlo, será con un estado, como se
-- hace con los retos.
