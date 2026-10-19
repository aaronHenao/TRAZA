-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-322: moderación del foro con IA
-- (SCRUM-336, SCRUM-337, SCRUM-338, SCRUM-339)
--
-- Corre esto DESPUÉS de 0028_foro_tiempo_real.sql.
--
-- Antes de aplicarla:
--   1. En Vault, el secreto que comparte con la Edge Function:
--        select vault.create_secret('<secreto>', 'moderacion_webhook_secret');
--      El mismo valor va en `supabase secrets set
--      MODERACION_WEBHOOK_SECRET=<secreto>`. Nunca en el repositorio.
--   2. La Edge Function `moderar-foro` desplegada. Sin ella (o sin el
--      secreto) todo queda "en revisión" y el administrador lo decide
--      a mano: no se pierde nada.
--
-- El flujo:
--   - Lo que escribe un corredor (publicación, comentario o edición)
--     queda `en_revision` y se anota en `moderaciones_foro`.
--   - Un trigger avisa a la Edge Function (pg_net), que le pregunta a
--     Nemotron y devuelve el veredicto con `aplicar_veredicto_ia`:
--     aprobada → se publica; rechazada → queda fuera con su motivo;
--     pendiente → la IA dudó y lo decide el administrador con
--     `decidir_moderacion`.
--   - Una edición no toca lo publicado hasta que se aprueba: los demás
--     siguen leyendo la versión anterior.
--   - Lo del administrador se publica sin pasar por la IA.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Estados del contenido
--
-- `retenida` (0020) nunca se llegó a usar: pasa a ser `pendiente`.
-- -------------------------------------------------------------
alter table publicaciones_foro
  drop constraint publicaciones_foro_estado_valido;

update publicaciones_foro set estado = 'pendiente' where estado = 'retenida';

alter table publicaciones_foro
  add constraint publicaciones_foro_estado_valido
    check (estado in ('en_revision', 'publicada', 'pendiente', 'rechazada', 'eliminada'));

-- Los comentarios que ya existen quedan publicados.
alter table comentarios_foro
  add column estado text not null default 'publicada',
  add column motivo_moderacion text;

alter table comentarios_foro
  add constraint comentarios_foro_estado_valido
    check (estado in ('en_revision', 'publicada', 'pendiente', 'rechazada', 'eliminada'));

-- -------------------------------------------------------------
-- 2. moderaciones_foro: cola, historial y faltas
--
-- Una fila por cada cosa que se modera. Guarda una copia del texto
-- analizado: en una edición es lo único que existe del texto nuevo
-- hasta que se aprueba, y en un rechazo es lo que el autor y el
-- administrador necesitan ver.
--
-- Las faltas de un usuario (criterio 5, SCRUM-338) son sus filas
-- `rechazada`.
-- -------------------------------------------------------------
create table moderaciones_foro (
  id                  uuid primary key default gen_random_uuid(),
  tipo                text not null,
  publicacion_id      uuid not null references publicaciones_foro(id) on delete cascade,
  -- Solo en los comentarios. En ellos, `publicacion_id` es la publicación
  -- comentada.
  comentario_id       uuid references comentarios_foro(id) on delete cascade,
  autor_id            uuid not null references auth.users(id) on delete cascade,
  -- Copia del nombre, por lo mismo que en publicaciones_foro: `perfiles`
  -- solo deja leer el perfil propio.
  autor_nombre        text not null,
  accion              text not null,
  -- Solo en las publicaciones.
  titulo              text,
  contenido           text not null,
  estado              text not null default 'en_revision',
  -- Lo que leen el autor y el administrador. En lo pendiente explica la
  -- duda de la IA; solo lo ve el administrador.
  motivo              text,
  -- Tipo de infracción en español (criterio 4).
  categorias          text[] not null default '{}',
  -- Quién decidió: 'ia' o 'admin'. Null mientras nadie decide.
  responsable         text,
  responsable_id      uuid references auth.users(id) on delete set null,
  responsable_nombre  text,
  -- Respuesta cruda de Nemotron, para auditar una decisión.
  veredicto_ia        jsonb,
  fecha_solicitud     timestamptz not null default now(),
  fecha_decision      timestamptz,
  -- El autor ya vio el rechazo (el contador del foro baja).
  vista_por_autor     boolean not null default false,

  constraint moderaciones_foro_tipo_valido
    check (tipo in ('publicacion', 'comentario')),
  constraint moderaciones_foro_accion_valida
    check (accion in ('creacion', 'edicion')),
  constraint moderaciones_foro_estado_valido
    check (estado in ('en_revision', 'aprobada', 'pendiente', 'rechazada')),
  constraint moderaciones_foro_responsable_valido
    check (responsable in ('ia', 'admin')),
  constraint moderaciones_foro_comentario_coherente
    check ((tipo = 'comentario') = (comentario_id is not null)),
  constraint moderaciones_foro_titulo_coherente
    check ((tipo = 'publicacion') = (titulo is not null))
);

-- "Mis rechazados" y las faltas de cada autor.
create index moderaciones_foro_autor_idx
  on moderaciones_foro (autor_id, fecha_solicitud desc);

-- Las pestañas de la moderación.
create index moderaciones_foro_estado_idx
  on moderaciones_foro (estado, fecha_solicitud desc);

-- Una sola edición abierta por publicación o comentario: si se pudiera
-- editar encima de otra en revisión, no quedaría claro cuál se aprueba.
create unique index moderaciones_foro_una_edicion_abierta
  on moderaciones_foro ((coalesce(comentario_id, publicacion_id)))
  where accion = 'edicion' and estado in ('en_revision', 'pendiente');

-- -------------------------------------------------------------
-- RLS
--
-- El autor lee lo suyo; el administrador, todo. Nadie escribe desde
-- la app: las filas las crean los triggers y las cambian las
-- funciones de abajo, que corren como su dueño.
-- -------------------------------------------------------------
alter table moderaciones_foro enable row level security;

create policy "el autor ve la moderación de lo suyo"
  on moderaciones_foro for select
  using (auth.uid() = autor_id);

create policy "el administrador ve toda la moderación"
  on moderaciones_foro for select
  using (public.es_admin());

-- -------------------------------------------------------------
-- 3. Lo que se ve de los comentarios
--
-- Como en las publicaciones: lo publicado lo ve cualquiera, lo suyo
-- lo ve el autor en cualquier estado y el administrador lo ve todo
-- (esa policy, de 0021, no cambia).
-- -------------------------------------------------------------
drop policy "los comentarios de lo publicado los lee cualquier usuario autenticado"
  on comentarios_foro;

create policy "los comentarios publicados de lo publicado los lee cualquier usuario autenticado"
  on comentarios_foro for select
  using (
    auth.role() = 'authenticated'
    and estado = 'publicada'
    and exists (
      select 1
      from publicaciones_foro p
      where p.id = publicacion_id
        and p.estado = 'publicada'
    )
  );

create policy "el autor ve sus propios comentarios"
  on comentarios_foro for select
  using (auth.uid() = autor_id);

-- -------------------------------------------------------------
-- 4. Al crear: en revisión y a la cola
-- -------------------------------------------------------------
create or replace function public.preparar_publicacion_foro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(nullif(btrim(p.nombre), ''), 'Corredor'),
         p.rol = 'admin'
    into new.autor_nombre, new.autor_es_admin
  from perfiles p
  where p.id = new.autor_id;

  -- Sin perfil (no debería pasar: lo crea handle_new_user).
  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');
  new.autor_es_admin := coalesce(new.autor_es_admin, false);
  -- Lo del administrador no pasa por la IA.
  new.estado := case when new.autor_es_admin then 'publicada' else 'en_revision' end;
  new.motivo_moderacion := null;
  new.fecha_creacion := now();
  return new;
end;
$$;

create or replace function public.preparar_comentario_foro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(nullif(btrim(p.nombre), ''), 'Corredor'),
         p.rol = 'admin'
    into new.autor_nombre, new.autor_es_admin
  from perfiles p
  where p.id = new.autor_id;

  new.autor_nombre := coalesce(new.autor_nombre, 'Corredor');
  new.autor_es_admin := coalesce(new.autor_es_admin, false);
  new.estado := case when new.autor_es_admin then 'publicada' else 'en_revision' end;
  new.motivo_moderacion := null;
  new.fecha_creacion := now();
  return new;
end;
$$;

create function public.solicitar_moderacion_publicacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'en_revision' then
    insert into moderaciones_foro
      (tipo, publicacion_id, autor_id, autor_nombre, accion, titulo, contenido)
    values
      ('publicacion', new.id, new.autor_id, new.autor_nombre, 'creacion',
       new.titulo, new.contenido);
  end if;
  return new;
end;
$$;

create trigger publicaciones_foro_solicitar_moderacion
  after insert on publicaciones_foro
  for each row execute function public.solicitar_moderacion_publicacion();

create function public.solicitar_moderacion_comentario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'en_revision' then
    insert into moderaciones_foro
      (tipo, publicacion_id, comentario_id, autor_id, autor_nombre, accion, contenido)
    values
      ('comentario', new.publicacion_id, new.id, new.autor_id, new.autor_nombre,
       'creacion', new.contenido);
  end if;
  return new;
end;
$$;

create trigger comentarios_foro_solicitar_moderacion
  after insert on comentarios_foro
  for each row execute function public.solicitar_moderacion_comentario();

-- -------------------------------------------------------------
-- 5. Quién cambia el estado
--
-- Reemplaza las funciones de 0025 y 0027. El estado y el motivo solo
-- cambian dentro de `resolver_moderacion`, que lo anuncia con
-- `traza.moderando` (vale solo para su transacción). Lo demás sigue
-- igual: columnas fijas, versión anterior guardada y fecha de edición.
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
  new.fecha_creacion := old.fecha_creacion;

  if coalesce(current_setting('traza.moderando', true), '') <> 'on' then
    new.estado := old.estado;
    new.motivo_moderacion := old.motivo_moderacion;
  end if;

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

create or replace function public.proteger_comentario_foro()
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

  if coalesce(current_setting('traza.moderando', true), '') <> 'on' then
    new.estado := old.estado;
    new.motivo_moderacion := old.motivo_moderacion;
  end if;

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

-- -------------------------------------------------------------
-- 6. Editar pasa por la moderación
--
-- Sin policies de update: el autor ya no escribe la fila visible.
-- Edita con estas funciones, que dejan el texto nuevo en la cola
-- (o lo aplican directo si es el administrador).
--
-- Errores que traduce la app:
--   42501  no es suyo, o ya no está publicado
--   23514  el texto no cumple los límites (los de 0020 y 0021)
--   TZ409  ya tiene una edición en revisión
-- -------------------------------------------------------------
drop policy "el autor edita lo suyo mientras esté publicado"
  on publicaciones_foro;

drop policy "el autor edita su comentario mientras la publicación esté publicada"
  on comentarios_foro;

-- Devuelve la fila de la cola, o null si el texto no cambió.
create function public.editar_publicacion_foro(
  p_id uuid,
  p_titulo text,
  p_contenido text
)
returns moderaciones_foro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_publicacion publicaciones_foro;
  v_moderacion moderaciones_foro;
  v_titulo text := btrim(coalesce(p_titulo, ''));
  v_contenido text := btrim(coalesce(p_contenido, ''));
  v_es_admin boolean := public.es_admin();
begin
  select * into v_publicacion
  from publicaciones_foro
  where id = p_id
  for update;

  if v_publicacion.id is null
     or v_publicacion.autor_id is distinct from auth.uid()
     or v_publicacion.estado <> 'publicada' then
    raise exception 'La publicación no está disponible para editar'
      using errcode = '42501';
  end if;

  if length(v_titulo) not between 1 and 120
     or length(v_contenido) not between 1 and 2000 then
    raise exception 'El título o el contenido no cumplen los límites'
      using errcode = '23514';
  end if;

  if v_titulo = v_publicacion.titulo and v_contenido = v_publicacion.contenido then
    return null;
  end if;

  begin
    insert into moderaciones_foro
      (tipo, publicacion_id, autor_id, autor_nombre, accion, titulo, contenido,
       estado, responsable, responsable_id, responsable_nombre, fecha_decision)
    values
      ('publicacion', p_id, v_publicacion.autor_id, v_publicacion.autor_nombre,
       'edicion', v_titulo, v_contenido,
       case when v_es_admin then 'aprobada' else 'en_revision' end,
       case when v_es_admin then 'admin' end,
       case when v_es_admin then auth.uid() end,
       case when v_es_admin then v_publicacion.autor_nombre end,
       case when v_es_admin then now() end)
    returning * into v_moderacion;
  exception when unique_violation then
    raise exception 'Ya hay una edición en revisión' using errcode = 'TZ409';
  end;

  if v_es_admin then
    update publicaciones_foro
       set titulo = v_titulo, contenido = v_contenido
     where id = p_id;
  end if;

  return v_moderacion;
end;
$$;

create function public.editar_comentario_foro(
  p_id uuid,
  p_contenido text
)
returns moderaciones_foro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comentario comentarios_foro;
  v_moderacion moderaciones_foro;
  v_contenido text := btrim(coalesce(p_contenido, ''));
  v_es_admin boolean := public.es_admin();
begin
  select c.* into v_comentario
  from comentarios_foro c
  join publicaciones_foro p on p.id = c.publicacion_id
  where c.id = p_id
    and p.estado = 'publicada'
  for update of c;

  if v_comentario.id is null
     or v_comentario.autor_id is distinct from auth.uid()
     or v_comentario.estado <> 'publicada' then
    raise exception 'El comentario no está disponible para editar'
      using errcode = '42501';
  end if;

  if length(v_contenido) not between 1 and 500 then
    raise exception 'El comentario no cumple los límites'
      using errcode = '23514';
  end if;

  if v_contenido = v_comentario.contenido then
    return null;
  end if;

  begin
    insert into moderaciones_foro
      (tipo, publicacion_id, comentario_id, autor_id, autor_nombre, accion,
       contenido, estado, responsable, responsable_id, responsable_nombre,
       fecha_decision)
    values
      ('comentario', v_comentario.publicacion_id, p_id, v_comentario.autor_id,
       v_comentario.autor_nombre, 'edicion', v_contenido,
       case when v_es_admin then 'aprobada' else 'en_revision' end,
       case when v_es_admin then 'admin' end,
       case when v_es_admin then auth.uid() end,
       case when v_es_admin then v_comentario.autor_nombre end,
       case when v_es_admin then now() end)
    returning * into v_moderacion;
  exception when unique_violation then
    raise exception 'Ya hay una edición en revisión' using errcode = 'TZ409';
  end;

  if v_es_admin then
    update comentarios_foro set contenido = v_contenido where id = p_id;
  end if;

  return v_moderacion;
end;
$$;

-- -------------------------------------------------------------
-- 7. Resolver una moderación
--
-- Lo único que cambia el estado del contenido. No se llama desde la
-- app: lo usan `aplicar_veredicto_ia` (la Edge Function) y
-- `decidir_moderacion` (el administrador).
-- -------------------------------------------------------------
create function public.resolver_moderacion(
  p_id uuid,
  p_estado text,
  p_motivo text,
  p_categorias text[],
  p_responsable text,
  p_responsable_id uuid,
  p_veredicto jsonb
)
returns moderaciones_foro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moderacion moderaciones_foro;
  v_estado_contenido text;
  v_motivo_contenido text;
  v_responsable_nombre text;
begin
  if p_estado not in ('aprobada', 'pendiente', 'rechazada') then
    raise exception 'Estado de moderación inválido: %', p_estado
      using errcode = '22023';
  end if;

  if p_responsable = 'admin' then
    select coalesce(nullif(btrim(nombre), ''), 'Administrador')
      into v_responsable_nombre
    from perfiles
    where id = p_responsable_id;
    v_responsable_nombre := coalesce(v_responsable_nombre, 'Administrador');
  else
    v_responsable_nombre := 'Moderación automática';
  end if;

  update moderaciones_foro
     set estado = p_estado,
         motivo = case when p_estado = 'aprobada' then null else p_motivo end,
         categorias = case when p_estado = 'aprobada' then '{}'
                           else coalesce(p_categorias, '{}') end,
         responsable = p_responsable,
         responsable_id = p_responsable_id,
         responsable_nombre = v_responsable_nombre,
         veredicto_ia = coalesce(p_veredicto, veredicto_ia),
         fecha_decision = now()
   where id = p_id
  returning * into v_moderacion;

  -- Deja a los triggers `proteger_*` cambiar estado y motivo, solo en
  -- esta transacción.
  perform set_config('traza.moderando', 'on', true);

  if v_moderacion.accion = 'creacion' then
    v_estado_contenido := case p_estado
      when 'aprobada' then 'publicada'
      when 'rechazada' then 'rechazada'
      else 'pendiente'
    end;
    v_motivo_contenido := case when p_estado = 'rechazada' then p_motivo end;

    if v_moderacion.tipo = 'publicacion' then
      update publicaciones_foro
         set estado = v_estado_contenido, motivo_moderacion = v_motivo_contenido
       where id = v_moderacion.publicacion_id
         and estado in ('en_revision', 'pendiente');
    else
      update comentarios_foro
         set estado = v_estado_contenido, motivo_moderacion = v_motivo_contenido
       where id = v_moderacion.comentario_id
         and estado in ('en_revision', 'pendiente');
    end if;

  -- Una edición aprobada reemplaza el texto; el trigger guarda la
  -- versión anterior. Rechazada o pendiente, lo publicado no cambia.
  elsif p_estado = 'aprobada' then
    if v_moderacion.tipo = 'publicacion' then
      update publicaciones_foro
         set titulo = v_moderacion.titulo, contenido = v_moderacion.contenido
       where id = v_moderacion.publicacion_id
         and estado = 'publicada';
    else
      update comentarios_foro
         set contenido = v_moderacion.contenido
       where id = v_moderacion.comentario_id
         and estado = 'publicada';
    end if;
  end if;

  perform set_config('traza.moderando', 'off', true);

  return v_moderacion;
end;
$$;

-- El veredicto de la IA. Solo actúa sobre lo que sigue en revisión:
-- si el administrador ya decidió (o el aviso llegó dos veces), no
-- cambia nada y devuelve la fila como está.
create function public.aplicar_veredicto_ia(
  p_moderacion_id uuid,
  p_estado text,
  p_motivo text,
  p_categorias text[],
  p_veredicto jsonb
)
returns moderaciones_foro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moderacion moderaciones_foro;
begin
  select * into v_moderacion
  from moderaciones_foro
  where id = p_moderacion_id
  for update;

  if v_moderacion.id is null or v_moderacion.estado <> 'en_revision' then
    return v_moderacion;
  end if;

  return public.resolver_moderacion(
    p_moderacion_id, p_estado, p_motivo, p_categorias, 'ia', null, p_veredicto
  );
end;
$$;

-- La decisión del administrador sobre lo que la IA dejó pendiente (o
-- lo que sigue en revisión porque la IA no respondió). Rechazar exige
-- motivo: es lo que lee el autor.
create function public.decidir_moderacion(
  p_moderacion_id uuid,
  p_aprobar boolean,
  p_motivo text
)
returns moderaciones_foro
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moderacion moderaciones_foro;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador modera el foro'
      using errcode = '42501';
  end if;

  if not p_aprobar and v_motivo is null then
    raise exception 'Rechazar exige un motivo' using errcode = '23514';
  end if;

  select * into v_moderacion
  from moderaciones_foro
  where id = p_moderacion_id
  for update;

  if v_moderacion.id is null
     or v_moderacion.estado not in ('en_revision', 'pendiente') then
    raise exception 'La moderación ya fue resuelta' using errcode = 'TZ409';
  end if;

  return public.resolver_moderacion(
    p_moderacion_id,
    case when p_aprobar then 'aprobada' else 'rechazada' end,
    v_motivo,
    -- Lo que la IA hubiera marcado se conserva si el admin confirma.
    case when p_aprobar then '{}' else v_moderacion.categorias end,
    'admin',
    auth.uid(),
    null
  );
end;
$$;

-- El autor abrió "Mis rechazados": el contador del foro vuelve a cero.
create function public.marcar_rechazos_vistos()
returns integer
language sql
security definer
set search_path = public
as $$
  with vistas as (
    update moderaciones_foro
       set vista_por_autor = true
     where autor_id = auth.uid()
       and estado = 'rechazada'
       and not vista_por_autor
    returning 1
  )
  select count(*)::integer from vistas;
$$;

-- Quién ejecuta qué. Postgres deja ejecutar cualquier función a
-- PUBLIC por defecto: se quita y se da solo lo necesario.
revoke execute on function public.resolver_moderacion(uuid, text, text, text[], text, uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.aplicar_veredicto_ia(uuid, text, text, text[], jsonb)
  from public, anon, authenticated;
grant execute on function public.aplicar_veredicto_ia(uuid, text, text, text[], jsonb)
  to service_role;

revoke execute on function public.editar_publicacion_foro(uuid, text, text) from public, anon;
revoke execute on function public.editar_comentario_foro(uuid, text) from public, anon;
revoke execute on function public.decidir_moderacion(uuid, boolean, text) from public, anon;
revoke execute on function public.marcar_rechazos_vistos() from public, anon;
grant execute on function public.editar_publicacion_foro(uuid, text, text) to authenticated;
grant execute on function public.editar_comentario_foro(uuid, text) to authenticated;
grant execute on function public.decidir_moderacion(uuid, boolean, text) to authenticated;
grant execute on function public.marcar_rechazos_vistos() to authenticated;

-- -------------------------------------------------------------
-- 8. Aviso a la Edge Function
--
-- pg_net encola el POST y no bloquea el insert. La función responde
-- de una vez y sigue trabajando en segundo plano, así que el timeout
-- corto no corta el análisis.
--
-- Si el secreto no está en Vault, no se avisa: la fila queda en
-- revisión y el administrador la decide a mano.
-- -------------------------------------------------------------
create extension if not exists pg_net with schema extensions;

create function public.avisar_moderacion_foro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secreto text;
begin
  if new.estado <> 'en_revision' then
    return new;
  end if;

  select decrypted_secret into v_secreto
  from vault.decrypted_secrets
  where name = 'moderacion_webhook_secret';

  if v_secreto is null then
    raise warning 'Falta moderacion_webhook_secret en Vault: la moderación % queda en revisión', new.id;
    return new;
  end if;

  perform net.http_post(
    url := 'https://prrumhnwizdirntqvynk.supabase.co/functions/v1/moderar-foro',
    body := jsonb_build_object('moderacion_id', new.id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-traza-secreto', v_secreto
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$$;

create trigger moderaciones_foro_avisar
  after insert on moderaciones_foro
  for each row execute function public.avisar_moderacion_foro();

-- -------------------------------------------------------------
-- 9. Tiempo real
--
-- El autor se entera del veredicto sin refrescar (criterio 5). Las
-- policies de select hacen que a cada uno solo le llegue lo suyo.
-- -------------------------------------------------------------
alter publication supabase_realtime add table moderaciones_foro;

-- =============================================================
-- Verificación (SQL Editor, después de aplicar)
--
-- 1. Las funciones que la app no debe poder llamar:
--      select has_function_privilege('authenticated',
--        'public.aplicar_veredicto_ia(uuid, text, text, text[], jsonb)', 'execute');
--      select has_function_privilege('authenticated',
--        'public.resolver_moderacion(uuid, text, text, text[], text, uuid, jsonb)', 'execute');
--    Las dos deben dar false.
--
-- 2. Nadie escribe la cola ni el estado desde la app: no hay policies
--    de insert/update/delete en moderaciones_foro ni de update en
--    publicaciones_foro / comentarios_foro.
--      select tablename, policyname, cmd from pg_policies
--       where tablename in ('moderaciones_foro', 'publicaciones_foro', 'comentarios_foro')
--       order by 1, 3;
--
-- 3. Con la app, publicar algo como corredor y revisar la cola:
--      select estado, responsable, motivo, categorias, fecha_decision
--        from moderaciones_foro order by fecha_solicitud desc limit 5;
--    Si se queda en `en_revision`, revisar las respuestas de pg_net:
--      select status_code, content, error_msg
--        from net._http_response order by created desc limit 5;
-- =============================================================
