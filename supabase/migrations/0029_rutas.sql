-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-241: rutas de la comunidad
--
-- Una ruta es el recorrido de un entrenamiento finalizado que su
-- autor ofrece a los demás. Nace `en_revision`: publicarla no la
-- publica, la manda a revisión del Runner Experto (criterio 1).
--
-- Decisiones:
--
--   · El trazado va en `jsonb`, no en PostGIS. La base solo
--     tiene `pgcrypto` y habilitar la extensión obligaría a Dart
--     a hablar WKT/GeoJSON. Con `inicio_latitud/longitud` en
--     columnas propias e indexadas, "las rutas cercanas" de
--     HU-29/HU-30 se resuelve con una consulta por caja.
--
--   · El trazado se copia, no se apunta a `puntos_gps`. La
--     policy de `entrenamientos` (0001) es `for all`, así que el
--     autor puede borrar el entrenamiento del que nació la ruta.
--     Una ruta que la comunidad ya usa no se puede ir con él, y
--     por eso `entrenamiento_id` es `on delete set null`: deja
--     de saberse de dónde salió, pero la ruta sigue ahí.
--
--   · `autor_nombre` es una copia, como en `publicaciones_foro`
--     (0020): `perfiles` solo deja leer el perfil propio, así
--     que sin esta columna nadie vería de quién es cada ruta.
--     La pone el trigger, no el cliente.
--
--   · `distancia_km` admite nulo a propósito. El criterio 4 de
--     SCRUM-240 pide avisar cuando la distancia no esté
--     registrada, así que ese caso tiene que poder existir.
--     Aquí el trigger la deja en nulo —el cliente no la
--     inventa—; quien la calcula al guardar es la migración de
--     la subtarea siguiente.
--
--   · Sin policies de update ni de delete, igual que hizo 0020
--     con el foro: aprobar y rechazar una ruta son de la HU del
--     Runner Experto, no de esta. Lo que sí se le da es la
--     lectura de lo que está en revisión, que es lo que su
--     pantalla necesita para existir.
--
-- Lo que NO hace esta migración:
--
--   · No toca `publicaciones_foro`. Que una ruta aprobada
--     aparezca en el foro con su autoría es otra subtarea.
--   · No notifica nada: la bandeja de notificaciones es otra
--     subtarea también.
--
-- Corre esto DESPUÉS de 0011_roles_usuario.sql (de ahí salen
-- `es_experto()` y `es_admin()`).
-- =============================================================

create table rutas (
  id                 uuid primary key default gen_random_uuid(),
  autor_id           uuid not null references auth.users(id) on delete cascade,
  -- Copia del nombre al crear la ruta. La pone el trigger.
  autor_nombre       text not null,
  -- De qué entrenamiento salió. Se queda en nulo si el autor lo
  -- borra; la ruta publicada no se va con él.
  entrenamiento_id   uuid references entrenamientos(id) on delete set null,
  nombre             text not null,
  descripcion        text,
  -- Lista ordenada de puntos: [{"lat": 6.2, "lng": -75.5}, ...].
  -- El orden es el del recorrido.
  trazado            jsonb not null,
  -- Primer punto del trazado, aparte y en columnas propias para
  -- poder indexarlo. Lo copia el trigger desde `trazado`.
  inicio_latitud     double precision not null,
  inicio_longitud    double precision not null,
  distancia_km       numeric,
  estado             text not null default 'en_revision',
  motivo_rechazo     text,
  fecha_creacion     timestamptz not null default now(),
  fecha_publicacion  timestamptz
);

-- Los límites del nombre y la descripción son los mismos que
-- 0020 le puso al foro, para que las dos pantallas se comporten
-- igual ante un texto largo.
alter table rutas
  add constraint rutas_nombre_valido
    check (length(btrim(nombre)) between 1 and 120),
  add constraint rutas_descripcion_valida
    check (descripcion is null or length(btrim(descripcion)) <= 2000),
  add constraint rutas_estado_valido
    check (estado in ('en_revision', 'publicada', 'rechazada')),
  -- Una ruta es al menos dos puntos: con uno solo no hay
  -- recorrido que seguir. Es el criterio 3 —trazado
  -- obligatorio— puesto donde no se puede saltar.
  add constraint rutas_trazado_valido
    check (
      jsonb_typeof(trazado) = 'array'
      and jsonb_array_length(trazado) >= 2
    ),
  add constraint rutas_distancia_valida
    check (distancia_km is null or distancia_km > 0),
  add constraint rutas_inicio_valido
    check (
      inicio_latitud between -90 and 90
      and inicio_longitud between -180 and 180
    ),
  -- Criterio 4: una ruta publicada siempre puede decir cuándo se
  -- publicó. El trigger pone la fecha; esto garantiza que nadie
  -- la deje sin ella.
  add constraint rutas_publicada_con_fecha
    check (estado <> 'publicada' or fecha_publicacion is not null);

-- El apartado de rutas lista lo publicado, de lo más reciente a
-- lo más antiguo.
create index rutas_estado_fecha_idx
  on rutas (estado, fecha_publicacion desc);

-- "Mis rutas", incluidas las que siguen en revisión.
create index rutas_autor_idx
  on rutas (autor_id, fecha_creacion desc);

-- Para buscar por cercanía sin recorrer la tabla entera. Solo
-- las publicadas: las demás no se le ofrecen a nadie.
create index rutas_inicio_idx
  on rutas (inicio_latitud, inicio_longitud)
  where estado = 'publicada';

-- -------------------------------------------------------------
-- Lo que el cliente no decide
--
-- El nombre del autor, el estado y las fechas los pone la base.
-- Si el cliente pudiera mandarlos, cualquiera publicaría a
-- nombre de otro o se saltaría la revisión del experto.
--
-- El punto de inicio sale del propio trazado en vez de llegar
-- aparte: así no puede contradecirlo.
-- -------------------------------------------------------------
create function public.preparar_ruta()
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

  -- Un punto sin coordenadas rompería el mapa de quien siga la
  -- ruta, y el trazado se guarda una sola vez: más vale que no
  -- entre que arreglarlo después.
  if exists (
    select 1
    from jsonb_array_elements(new.trazado) as punto
    where jsonb_typeof(punto -> 'lat') <> 'number'
       or jsonb_typeof(punto -> 'lng') <> 'number'
  ) then
    raise exception
      'el trazado de la ruta tiene puntos sin coordenadas'
      using errcode = '23514';
  end if;

  new.inicio_latitud := (new.trazado -> 0 ->> 'lat')::double precision;
  new.inicio_longitud := (new.trazado -> 0 ->> 'lng')::double precision;

  new.estado := 'en_revision';
  new.motivo_rechazo := null;
  new.fecha_creacion := now();
  new.fecha_publicacion := null;
  -- La calcula la migración de la subtarea siguiente, a partir
  -- del entrenamiento del que salió la ruta.
  new.distancia_km := null;

  return new;
end;
$$;

create trigger rutas_preparar
  before insert on rutas
  for each row execute function public.preparar_ruta();

-- -------------------------------------------------------------
-- La fecha de publicación la sella la base
--
-- `rutas_publicada_con_fecha` exige que una ruta publicada tenga
-- su fecha. Esto la pone sola en el momento en que la ruta pasa
-- a publicada, así que quien apruebe —la pantalla del Runner
-- Experto, que es otra HU— solo tiene que cambiar el estado y no
-- se puede olvidar de la fecha que el criterio 4 necesita.
-- -------------------------------------------------------------
create function public.sellar_publicacion_de_ruta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'publicada' and old.estado <> 'publicada' then
    new.fecha_publicacion := coalesce(new.fecha_publicacion, now());
  end if;

  return new;
end;
$$;

create trigger rutas_sellar_publicacion
  before update on rutas
  for each row execute function public.sellar_publicacion_de_ruta();

-- -------------------------------------------------------------
-- RLS
--
-- Lo publicado lo ve cualquier usuario con sesión. El autor ve
-- además lo suyo mientras está en revisión o si se lo
-- rechazaron, el Runner Experto ve lo que tiene que revisar, y
-- el administrador lo ve todo.
--
-- Las policies de select se suman (OR), así que cada una solo
-- tiene que describir su caso.
-- -------------------------------------------------------------
alter table rutas enable row level security;

create policy "las rutas publicadas las ve cualquier usuario autenticado"
  on rutas for select
  using (auth.role() = 'authenticated' and estado = 'publicada');

create policy "el autor ve sus propias rutas"
  on rutas for select
  using (auth.uid() = autor_id);

create policy "el runner experto ve las rutas en revision"
  on rutas for select
  using (public.es_experto() and estado = 'en_revision');

create policy "el administrador ve todas las rutas"
  on rutas for select
  using (public.es_admin());

-- Una ruta se publica a nombre propio y nace de un entrenamiento
-- propio y terminado: es el recorrido que el autor hizo, no uno
-- que se invente ni el de otra persona. Después puede quedar en
-- nulo (el `on delete set null` de arriba), pero al crearla
-- tiene que estar.
create policy "el usuario registra rutas de sus propios entrenamientos"
  on rutas for insert
  with check (
    auth.uid() = autor_id
    and entrenamiento_id is not null
    and exists (
      select 1
      from entrenamientos e
      where e.id = rutas.entrenamiento_id
        and e.usuario_id = auth.uid()
        and e.estado = 'finalizado'
    )
  );

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. La tabla quedó con sus restricciones:
--
--   select conname
--   from pg_constraint
--   where conrelid = 'rutas'::regclass
--   order by conname;
--
--   Tienen que estar las seis `rutas_*` de arriba.
--
-- 2. El trigger rellena lo suyo. Con el id de un entrenamiento
--    finalizado tuyo:
--
--   insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
--   values (
--     (select usuario_id from entrenamientos where id = '<ENTRENAMIENTO>'),
--     '<ENTRENAMIENTO>',
--     'Prueba de ruta',
--     '[{"lat": 6.2442, "lng": -75.5812},
--       {"lat": 6.2450, "lng": -75.5800}]'::jsonb
--   )
--   returning autor_nombre, estado, inicio_latitud, distancia_km;
--
--   Debe devolver tu nombre, 'en_revision', 6.2442 y nulo.
--
-- 3. Un trazado roto no entra:
--
--   insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
--   values (
--     (select usuario_id from entrenamientos where id = '<ENTRENAMIENTO>'),
--     '<ENTRENAMIENTO>',
--     'Trazado roto',
--     '[{"lat": 6.2}, {"lat": 6.3, "lng": -75.5}]'::jsonb
--   );
--
--   Debe fallar con "el trazado de la ruta tiene puntos sin
--   coordenadas".
--
-- 4. Y un trazado de un solo punto tampoco:
--
--   ... '[{"lat": 6.2442, "lng": -75.5812}]'::jsonb
--
--   Debe fallar por `rutas_trazado_valido`.
--
-- 5. Al publicarla, la fecha se pone sola:
--
--   update rutas set estado = 'publicada'
--   where nombre = 'Prueba de ruta'
--   returning estado, fecha_publicacion;
--
--   Debe devolver 'publicada' con la fecha de ahora. Desde la app
--   este update no pasa (no hay policy de update todavía, es de
--   la HU del Runner Experto); en el SQL Editor sí, porque ahí la
--   sesión es dueña de la tabla y RLS no le aplica.
--
-- Para dejar la base limpia después de probar:
--
--   delete from rutas where nombre in ('Prueba de ruta', 'Trazado roto');
-- -------------------------------------------------------------
