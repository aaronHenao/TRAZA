-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-241 y SCRUM-242: notificaciones
--
-- Dos criterios piden avisarle algo al usuario: que su ruta se
-- publicó (criterio 2 de SCRUM-241) y que el administrador le
-- retiró una publicación y por qué (criterio 2 de SCRUM-242).
-- Las dos cosas pasan cuando él no está mirando, así que hacen
-- falta en algún sitio donde las encuentre después.
--
-- Son notificaciones dentro de la app: una tabla y una bandeja.
-- No hay push al teléfono —eso es FCM, configuración nativa en
-- Android y iOS y una función en el servidor, o sea otra
-- historia— y los criterios no lo piden.
--
-- Decisiones:
--
--   · El texto se guarda escrito. Lo redacta quien crea la
--     notificación, que es la base, porque es la que sabe el
--     nombre de la ruta o el motivo del retiro. Guardar en su
--     lugar un código y armar la frase en Dart no compra nada
--     mientras la app esté en un solo idioma, y obligaría a
--     repetir cada plantilla en el cliente.
--
--   · `entidad_id` dice a qué apunta el aviso; qué cosa es se
--     deduce del `tipo`. Sin clave foránea a propósito: apunta a
--     tablas distintas según el tipo, y una notificación es un
--     hecho que ya ocurrió — si la ruta desaparece, el aviso de
--     que se publicó sigue siendo cierto.
--
--   · El cliente no crea ni borra notificaciones. Solo puede
--     leer las suyas y marcarlas como leídas, y eso último lo
--     vigila un trigger: con la publishable key, "solo puedo
--     cambiar esta columna" tiene que estar escrito en la base.
--
--   · `crear_notificacion()` es la puerta para escribirlas y se
--     le quita el permiso de ejecución a los usuarios: si
--     cualquiera pudiera llamarla, cualquiera podría mandarle un
--     aviso a cualquiera. La llaman los triggers, que corren con
--     los privilegios de su dueño.
--
-- Corre esto DESPUÉS de 0031_una_ruta_por_entrenamiento.sql.
-- =============================================================

create table notificaciones (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references auth.users(id) on delete cascade,
  tipo            text not null,
  titulo          text not null,
  mensaje         text not null,
  -- A qué apunta el aviso (la ruta, la publicación). Qué tabla es
  -- lo dice `tipo`.
  entidad_id      uuid,
  -- Cuándo la leyó. Nulo mientras no la haya visto: es lo que
  -- cuenta el contador de la campana.
  leida_en        timestamptz,
  fecha_creacion  timestamptz not null default now()
);

alter table notificaciones
  -- Añadir un tipo es cambiar esta restricción en otra migración.
  -- `ruta_rechazada` queda previsto para la HU de la revisión del
  -- Runner Experto: el aviso lo crea quien implemente el rechazo.
  add constraint notificaciones_tipo_valido
    check (tipo in ('ruta_publicada', 'ruta_rechazada', 'publicacion_retirada')),
  add constraint notificaciones_titulo_valido
    check (length(btrim(titulo)) between 1 and 120),
  add constraint notificaciones_mensaje_valido
    check (length(btrim(mensaje)) between 1 and 500);

-- La bandeja: las de un usuario, de la más reciente a la más
-- antigua.
create index notificaciones_usuario_fecha_idx
  on notificaciones (usuario_id, fecha_creacion desc);

-- El contador de la campana, que se pide en cada portada.
create index notificaciones_sin_leer_idx
  on notificaciones (usuario_id)
  where leida_en is null;

-- -------------------------------------------------------------
-- La puerta para crear notificaciones
--
-- La llaman los triggers que avisan de algo (la ruta publicada,
-- la publicación retirada). No la llama el cliente: por eso
-- abajo se le quita el permiso de ejecución.
-- -------------------------------------------------------------
create function public.crear_notificacion(
  p_usuario uuid,
  p_tipo text,
  p_titulo text,
  p_mensaje text,
  p_entidad uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into notificaciones (usuario_id, tipo, titulo, mensaje, entidad_id)
  values (p_usuario, p_tipo, p_titulo, p_mensaje, p_entidad)
  returning id into v_id;

  return v_id;
end;
$$;

-- Postgres le da `execute` a todo el mundo por defecto. Aquí no:
-- un usuario que pudiera llamarla le mandaría avisos falsos a
-- quien quisiera. Los triggers la pueden llamar igual, porque
-- dentro de una función `security definer` el usuario en curso es
-- su dueño.
revoke execute on function public.crear_notificacion(
  uuid, text, text, text, uuid
) from public, anon, authenticated;

-- -------------------------------------------------------------
-- Lo único que el cliente puede cambiar
-- -------------------------------------------------------------
create function public.solo_marcar_notificacion_leida()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.usuario_id is distinct from old.usuario_id
     or new.tipo is distinct from old.tipo
     or new.titulo is distinct from old.titulo
     or new.mensaje is distinct from old.mensaje
     or new.entidad_id is distinct from old.entidad_id
     or new.fecha_creacion is distinct from old.fecha_creacion then
    raise exception
      'de una notificacion solo se puede cambiar si esta leida'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger notificaciones_solo_leida
  before update on notificaciones
  for each row execute function public.solo_marcar_notificacion_leida();

-- -------------------------------------------------------------
-- RLS
--
-- Cada uno ve y marca las suyas. Sin policies de insert ni de
-- delete: las notificaciones las crea la base cuando pasa algo, y
-- un aviso que el usuario pudiera borrar dejaría de servir como
-- registro de que se le avisó.
-- -------------------------------------------------------------
alter table notificaciones enable row level security;

create policy "cada uno ve sus notificaciones"
  on notificaciones for select
  using (auth.uid() = usuario_id);

create policy "cada uno marca como leidas las suyas"
  on notificaciones for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Crear una a mano para ti (en el editor sí se puede: la
--    sesión es dueña de la función):
--
--   select public.crear_notificacion(
--     '<TU USUARIO>',
--     'ruta_publicada',
--     'Prueba',
--     'Esto es una notificacion de prueba.'
--   );
--
--   Desde la app, con sesión de usuario, esa misma llamada tiene
--   que fallar por permisos.
--
-- 2. Solo se puede cambiar `leida_en`:
--
--   update notificaciones set mensaje = 'otro' where titulo = 'Prueba';
--
--   Debe fallar con "de una notificacion solo se puede cambiar si
--   esta leida". Y esto tiene que pasar:
--
--   update notificaciones set leida_en = now() where titulo = 'Prueba';
--
-- Para dejar la base limpia:
--
--   delete from notificaciones where titulo = 'Prueba';
-- -------------------------------------------------------------
