-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-242: eliminar publicaciones del foro
-- (subtarea 1)
--
-- Criterios 1 y 3: el administrador retira una publicación
-- indicando el motivo, y queda asentado quién lo hizo, cuándo y
-- por qué.
--
-- Eliminar es una baja lógica, como en SCRUM-134 con los retos: la
-- fila se queda y pasa a `eliminada`. Si se borrara, la bitácora
-- apuntaría a algo que ya no existe, y los reportes que la
-- señalaron (0036) se irían con ella.
--
-- El estado `eliminada` ya lo admite `publicaciones_foro_estado_valido`
-- (0035) y `EstadoPublicacion.eliminada` ya lo lee la app: lo que
-- faltaba era quién lo pone. Nadie actualiza `publicaciones_foro`
-- directo (no hay policy de update, a propósito desde 0020): el
-- estado y el motivo los cambia `retirar_publicacion_foro`, que
-- corre como su dueño y le anuncia a los triggers `proteger_*` que
-- está moderando, igual que `resolver_moderacion` (0035).
--
-- Lo que no hace falta tocar:
--   · Ocultarla. La policy de select de 0020 solo muestra lo
--     `publicada`, salvo al autor y al administrador, y las
--     consultas del foro filtran por estado (subtarea 2).
--   · Sus comentarios. La policy de 0035 los condiciona a que su
--     publicación esté `publicada`: se van con ella.
--   · El tipo del aviso. `publicacion_retirada` está previsto en
--     `notificaciones` desde 0032 (y lo conserva 0045).
--
-- Corre esto DESPUÉS de 0051_retirada_recompensas.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La bitácora de moderación
--
-- Una fila por retiro. `moderaciones_foro` (0035) no sirve para
-- esto: es la cola de lo que espera un veredicto antes de
-- publicarse, no el registro de lo que se retiró después.
--
-- El nombre del administrador se copia al retirar, como hace
-- `resolver_moderacion` con `responsable_nombre`: así la bitácora
-- sigue diciendo quién fue aunque después cambie su perfil.
--
-- Hoy la única acción que se asienta es el retiro. Cuando haya
-- otra (restituir, por ejemplo), lleva su columna `accion` y esta
-- tabla deja de ser solo de retiros.
-- -------------------------------------------------------------
create table bitacora_moderacion_foro (
  id                   uuid primary key default gen_random_uuid(),
  publicacion_id       uuid not null
                         references publicaciones_foro(id) on delete cascade,
  administrador_id     uuid not null references auth.users(id),
  administrador_nombre text not null,
  motivo               text not null,
  fecha                timestamptz not null default now()
);

alter table bitacora_moderacion_foro
  add constraint bitacora_moderacion_foro_motivo_valido
    check (length(btrim(motivo)) between 1 and 300);

-- El historial completo, de lo más reciente a lo más antiguo.
create index bitacora_moderacion_foro_fecha_idx
  on bitacora_moderacion_foro (fecha desc);

-- Por qué se retiró esta publicación.
create index bitacora_moderacion_foro_publicacion_idx
  on bitacora_moderacion_foro (publicacion_id, fecha desc);

-- -------------------------------------------------------------
-- RLS
--
-- Solo el administrador la lee: es su registro de trabajo, y el
-- autor ya se enteró por su notificación, con el mismo motivo.
--
-- Sin policies de insert, update ni delete, a propósito: las filas
-- las escribe `retirar_publicacion_foro`, que corre como su dueño
-- y se salta RLS. Así nadie puede inventarse un retiro, cambiarle
-- el motivo ni borrar el rastro de uno.
-- -------------------------------------------------------------
alter table bitacora_moderacion_foro enable row level security;

create policy "el administrador lee la bitácora de moderación"
  on bitacora_moderacion_foro for select
  using (public.es_admin());

-- -------------------------------------------------------------
-- 2. Retirar una publicación
--
-- Hace las tres cosas en una transacción: retira, asienta y avisa.
-- Si algo falla, no queda una publicación retirada sin registro ni
-- un aviso de algo que sigue a la vista.
--
-- Devuelve la publicación como quedó, que es lo que la pantalla
-- del administrador necesita para refrescar su lista.
-- -------------------------------------------------------------
create function public.retirar_publicacion_foro(
  p_publicacion_id uuid,
  p_motivo text
)
returns publicaciones_foro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_publicacion publicaciones_foro;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_nombre text;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador retira publicaciones'
      using errcode = '42501';
  end if;

  -- El motivo no es opcional: es lo que se asienta en la bitácora
  -- (criterio 3) y lo que lee el autor (criterio 2).
  if v_motivo is null then
    raise exception 'Retirar una publicación exige un motivo'
      using errcode = '23514';
  end if;

  if length(v_motivo) > 300 then
    raise exception 'El motivo no puede pasar de 300 caracteres'
      using errcode = '23514';
  end if;

  -- `for update`: si dos administradores la retiran a la vez, el
  -- segundo encuentra la fila ya `eliminada` y se detiene, en vez
  -- de dejar dos asientos y dos avisos del mismo retiro.
  select * into v_publicacion
  from publicaciones_foro
  where id = p_publicacion_id
  for update;

  if v_publicacion.id is null then
    raise exception 'La publicación no existe' using errcode = 'TZ404';
  end if;

  if v_publicacion.estado = 'eliminada' then
    raise exception 'La publicación ya fue retirada' using errcode = 'TZ409';
  end if;

  select coalesce(nullif(btrim(nombre), ''), 'Administrador')
    into v_nombre
  from perfiles
  where id = auth.uid();
  v_nombre := coalesce(v_nombre, 'Administrador');

  -- Igual que `resolver_moderacion` (0035): el trigger
  -- `proteger_publicacion_foro` devuelve el estado y el motivo a lo
  -- que eran salvo que se le anuncie que esto es moderación. Vale
  -- solo para esta transacción.
  perform set_config('traza.moderando', 'on', true);

  update publicaciones_foro
     set estado = 'eliminada',
         motivo_moderacion = v_motivo
   where id = p_publicacion_id
  returning * into v_publicacion;

  perform set_config('traza.moderando', 'off', true);

  insert into bitacora_moderacion_foro
    (publicacion_id, administrador_id, administrador_nombre, motivo)
  values
    (p_publicacion_id, auth.uid(), v_nombre, v_motivo);

  -- El autor se entera con el motivo (criterio 2). El título de la
  -- publicación va en el mensaje: en la bandeja no se ve de qué
  -- publicación habla el aviso si no se dice.
  perform public.crear_notificacion(
    v_publicacion.autor_id,
    'publicacion_retirada',
    'Retiramos tu publicación',
    format('«%s» ya no se ve en el foro. Motivo: %s',
           v_publicacion.titulo, v_motivo),
    p_publicacion_id
  );

  return v_publicacion;
end;
$$;

-- Postgres le da `execute` a todo el mundo por defecto. La función
-- comprueba `es_admin()` por dentro, pero `anon` no tiene nada que
-- hacer aquí.
revoke execute on function public.retirar_publicacion_foro(uuid, text)
  from public, anon;
grant execute on function public.retirar_publicacion_foro(uuid, text)
  to authenticated;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- El SQL Editor corre como `postgres`, que además es el dueño de
-- las tablas: se salta RLS y `auth.uid()` le vuelve nulo. Así,
-- `es_admin()` da false y todo falla con 42501 aunque esté bien.
-- Hay que hacerse pasar por el usuario, con el selector de rol del
-- dashboard ("Impersonate a user") o con esta cabecera:
--
--   begin;
--   select set_config(
--     'request.jwt.claims',
--     json_build_object('sub', '<USUARIO>', 'role', 'authenticated')::text,
--     true
--   );
--   set local role authenticated;
--   -- ...la prueba...
--   commit;   -- o rollback, si no se quiere conservar
--
-- `set_config(..., true)` y `set local` solo valen dentro de su
-- transacción: la cabecera y la prueba van en la MISMA ejecución,
-- o la suplantación no se aplica. Reproduce RLS, no los permisos
-- de `grant`: como `postgres` se puede ejecutar lo que un
-- `authenticated` no podría. `reset role` vuelve a `postgres`.
--
-- Para encontrar con qué probar:
--
--   select id, nombre from perfiles where rol = 'admin';
--
--   select id, titulo, autor_id, estado
--   from publicaciones_foro
--   where estado = 'publicada'
--     and autor_id not in (select id from perfiles where rol = 'admin')
--   order by fecha_creacion desc
--   limit 10;
--
-- Si no hay ninguna, se publica una desde la app con una cuenta de
-- corredor (nace `en_revision`, 0035) y el administrador la aprueba
-- en /admin/foro.
--
-- Con la sesión de un ADMINISTRADOR, sobre una publicación que no
-- sea suya:
--
-- 1. Retirarla:
--
--   select estado, motivo_moderacion
--   from public.retirar_publicacion_foro(
--     '<PUBLICACION>', 'Lenguaje ofensivo'
--   );
--
--   Vuelve 'eliminada' con ese motivo.
--
-- 2. El asiento (criterio 3):
--
--   select administrador_nombre, motivo, fecha
--   from bitacora_moderacion_foro
--   where publicacion_id = '<PUBLICACION>';
--
--   Una fila, con tu nombre de perfil y el motivo.
--
-- 3. El aviso al autor (criterio 2):
--
--   select tipo, titulo, mensaje, entidad_id, leida_en
--   from notificaciones
--   where entidad_id = '<PUBLICACION>';
--
--   'publicacion_retirada', el motivo en el mensaje, apuntando a la
--   publicación y sin leer.
--
-- 4. Que no se retire dos veces:
--
--   select public.retirar_publicacion_foro('<PUBLICACION>', 'Otra vez');
--
--   Falla con 'La publicación ya fue retirada' (TZ409), y la
--   bitácora sigue con una sola fila.
--
-- 5. Que exija motivo:
--
--   select public.retirar_publicacion_foro('<OTRA PUBLICACION>', '   ');
--
--   Falla con 'Retirar una publicación exige un motivo' (23514).
--
-- 6. Que no exista la publicación:
--
--   select public.retirar_publicacion_foro(gen_random_uuid(), 'Spam');
--
--   Falla con 'La publicación no existe' (TZ404).
--
-- Y con la sesión de un CORREDOR:
--
-- 7. Que no pueda retirar:
--
--   select public.retirar_publicacion_foro('<OTRA PUBLICACION>', 'Spam');
--
--   Falla con 'Solo el administrador retira publicaciones' (42501).
--
-- 8. Que no lea la bitácora:
--
--   select count(*) from bitacora_moderacion_foro;
--
--   Devuelve 0, aunque haya filas.
--
-- 9. Que la publicación retirada ya no se le muestre:
--
--   select count(*) from publicaciones_foro where id = '<PUBLICACION>';
--
--   Devuelve 0 para cualquiera que no sea su autor ni el
--   administrador. Al autor le vuelve 1: la ve con su motivo, y de
--   las listas del foro la saca la app (subtarea 2).
--
-- Para dejar la base como estaba:
--
--   delete from notificaciones where entidad_id = '<PUBLICACION>';
--   delete from bitacora_moderacion_foro
--    where publicacion_id = '<PUBLICACION>';
--
--   -- Volver a publicarla es saltarse el trigger a mano, así que
--   -- las dos sentencias van juntas en la MISMA ejecución:
--   -- `traza.moderando` solo vale dentro de su transacción.
--   select set_config('traza.moderando', 'on', true);
--   update publicaciones_foro
--      set estado = 'publicada', motivo_moderacion = null
--    where id = '<PUBLICACION>';
-- -------------------------------------------------------------
