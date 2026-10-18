-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-321: validar la publicación de rutas
--
-- Una ruta publicada pasa por dos revisiones antes de que la vea
-- la comunidad: primero la del administrador y después la de un
-- Runner Experto. Cualquiera de los dos la puede rechazar, pero
-- solo con motivo.
--
-- Estados (columna `estado` de `rutas`, 0029):
--
--   en_revision       → pendiente de revisión del administrador
--   revision_experto  → pendiente de revisión del Runner Experto
--   publicada         → la ve toda la comunidad
--   rechazada         → la ve su autor, con el motivo
--
-- Decisiones:
--
--   · `en_revision` se queda como primera etapa en vez de crear
--     otro valor. `preparar_ruta()` (0030) obliga a que toda ruta
--     nazca así, y no hay que tocarla: lo que cambia es quién la
--     revisa primero. Las rutas que ya estaban en revisión caen
--     solas en la bandeja del administrador.
--
--   · El experto deja de ver lo que está `en_revision` (la policy
--     de 0029 se cambia por una de `revision_experto`): lo pide el
--     criterio 2, la ruta le llega cuando el administrador ya la
--     aprobó.
--
--   · Cada decisión queda en `revisiones_ruta`: quién, en qué
--     etapa, qué decidió y por qué. La ruta solo guarda su estado
--     actual; el registro dice cómo llegó ahí.
--
-- Lo que NO hace esta migración:
--
--   · No agrega policies de update a `rutas`. Las decisiones pasan
--     por una función que valida el rol y la etapa (abajo).
--   · No notifica el rechazo: eso es 0037.
--
-- Corre esto DESPUÉS de 0035_foro_moderacion_ia.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Los estados de la revisión (SCRUM-325)
-- -------------------------------------------------------------
alter table rutas
  drop constraint rutas_estado_valido;

alter table rutas
  add constraint rutas_estado_valido
    check (estado in ('en_revision', 'revision_experto', 'publicada', 'rechazada')),
  -- El motivo lo lee el autor en su notificación (0037): cabe en
  -- ella con el nombre de la ruta.
  add constraint rutas_motivo_rechazo_valido
    check (motivo_rechazo is null or length(btrim(motivo_rechazo)) between 1 and 300),
  -- Criterio 6: no hay rechazo sin motivo.
  add constraint rutas_rechazada_con_motivo
    check (estado <> 'rechazada' or motivo_rechazo is not null);

-- La bandeja de cada revisor lista lo pendiente, lo más antiguo
-- primero.
create index rutas_pendientes_idx
  on rutas (estado, fecha_creacion)
  where estado in ('en_revision', 'revision_experto');

-- -------------------------------------------------------------
-- 2. El Runner Experto ve solo lo que ya aprobó el administrador
-- -------------------------------------------------------------
drop policy "el runner experto ve las rutas en revision" on rutas;

create policy "el runner experto ve las rutas pendientes de su revision"
  on rutas for select
  using (public.es_experto() and estado = 'revision_experto');

-- -------------------------------------------------------------
-- 3. El registro de decisiones
-- -------------------------------------------------------------
create table revisiones_ruta (
  id              uuid primary key default gen_random_uuid(),
  ruta_id         uuid not null references rutas(id) on delete cascade,
  revisor_id      uuid not null references auth.users(id) on delete cascade,
  -- Copia del nombre, como `autor_nombre` en `rutas`: `perfiles`
  -- solo deja leer el propio.
  revisor_nombre  text not null,
  etapa           text not null,
  decision        text not null,
  motivo          text,
  fecha           timestamptz not null default now()
);

alter table revisiones_ruta
  add constraint revisiones_ruta_etapa_valida
    check (etapa in ('administrador', 'experto')),
  add constraint revisiones_ruta_decision_valida
    check (decision in ('aprobada', 'rechazada')),
  add constraint revisiones_ruta_motivo_valido
    check (motivo is null or length(btrim(motivo)) between 1 and 300),
  add constraint revisiones_ruta_rechazo_con_motivo
    check (decision <> 'rechazada' or motivo is not null);

create index revisiones_ruta_ruta_idx
  on revisiones_ruta (ruta_id, fecha);

-- Sin policies de insert, update ni delete: solo escribe la
-- función de decisión, que valida el rol. El administrador lo ve
-- todo y el experto lo que decidió él.
alter table revisiones_ruta enable row level security;

create policy "el administrador ve todas las revisiones de rutas"
  on revisiones_ruta for select
  using (public.es_admin());

create policy "el revisor ve sus propias decisiones"
  on revisiones_ruta for select
  using (auth.uid() = revisor_id);

-- -------------------------------------------------------------
-- 4. La decisión (SCRUM-326)
--
-- Es el único camino para cambiar el estado de una ruta desde la
-- app: `rutas` no tiene policy de update. La función sabe en qué
-- etapa está cada ruta y quién puede decidir en ella:
--
--   en_revision       → solo el administrador. Aprobar la manda
--                       al Runner Experto (criterio 2).
--   revision_experto  → solo el Runner Experto. Aprobar la
--                       publica (criterio 4): la fecha la sella
--                       `rutas_sellar_publicacion` (0029) y el
--                       aviso al autor lo da 0033.
--
-- Rechazar, en cualquiera de las dos, exige motivo (criterio 6)
-- y deja la ruta `rechazada`, sin pasar a la etapa siguiente
-- (criterios 3 y 5).
--
-- Errores:
--
--   42501  quien decide no tiene el rol de esa etapa, o es el
--          autor de la ruta
--   23514  rechazar sin motivo, o con uno de más de 300
--   TZ404  la ruta no existe
--   TZ409  la ruta ya no está pendiente de nadie (otro revisor
--          decidió primero)
-- -------------------------------------------------------------
create function public.decidir_revision_ruta(
  p_ruta_id uuid,
  p_aprobar boolean,
  p_motivo text
)
returns rutas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ruta rutas;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_etapa text;
  v_siguiente text;
  v_nombre text;
begin
  if not p_aprobar and v_motivo is null then
    raise exception 'Rechazar una ruta exige un motivo' using errcode = '23514';
  end if;

  if v_motivo is not null and length(v_motivo) > 300 then
    raise exception 'El motivo no puede pasar de 300 caracteres'
      using errcode = '23514';
  end if;

  -- `for update`: si el administrador y otro revisor deciden a la
  -- vez, el segundo espera y ve la ruta ya movida (TZ409).
  select * into v_ruta
  from rutas
  where id = p_ruta_id
  for update;

  if v_ruta.id is null then
    raise exception 'La ruta no existe' using errcode = 'TZ404';
  end if;

  if v_ruta.estado = 'en_revision' then
    if not public.es_admin() then
      raise exception 'Solo el administrador hace la primera revisión'
        using errcode = '42501';
    end if;
    v_etapa := 'administrador';
    v_siguiente := 'revision_experto';
  elsif v_ruta.estado = 'revision_experto' then
    if not public.es_experto() then
      raise exception 'Solo un Runner Experto hace la segunda revisión'
        using errcode = '42501';
    end if;
    v_etapa := 'experto';
    v_siguiente := 'publicada';
  else
    raise exception 'La ruta ya fue revisada' using errcode = 'TZ409';
  end if;

  -- Nadie aprueba lo suyo: la revisión es de otros ojos.
  if v_ruta.autor_id = auth.uid() then
    raise exception 'No puedes revisar tu propia ruta' using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(p.nombre), ''), 'Revisor')
    into v_nombre
  from perfiles p
  where p.id = auth.uid();

  insert into revisiones_ruta (ruta_id, revisor_id, revisor_nombre, etapa, decision, motivo)
  values (
    v_ruta.id,
    auth.uid(),
    coalesce(v_nombre, 'Revisor'),
    v_etapa,
    case when p_aprobar then 'aprobada' else 'rechazada' end,
    case when p_aprobar then null else v_motivo end
  );

  update rutas
     set estado = case when p_aprobar then v_siguiente else 'rechazada' end,
         motivo_rechazo = case when p_aprobar then null else v_motivo end
   where id = v_ruta.id
  returning * into v_ruta;

  return v_ruta;
end;
$$;

-- Postgres deja ejecutar cualquier función a PUBLIC por defecto:
-- se quita y se da solo a quien tiene sesión. El rol lo valida la
-- función por dentro.
revoke execute on function public.decidir_revision_ruta(uuid, boolean, text)
  from public, anon;
grant execute on function public.decidir_revision_ruta(uuid, boolean, text)
  to authenticated;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- En el SQL Editor la sesión no es un usuario de la app, así que
-- `auth.uid()` es nulo y la función diría 42501. Para probarla
-- como un usuario, simula su sesión dentro de una transacción:
--
--   begin;
--   select set_config('request.jwt.claims',
--     '{"sub": "<ID DEL ADMIN>", "role": "authenticated"}', true);
--   set local role authenticated;
--
--   select estado from public.decidir_revision_ruta('<RUTA>', true, null);
--   -- Debe devolver 'revision_experto'.
--
--   select public.decidir_revision_ruta('<RUTA>', false, '  ');
--   -- Debe fallar: "Rechazar una ruta exige un motivo" (ya está
--   -- en la etapa del experto, pero el motivo se valida primero).
--
--   rollback;
--
-- 1. El experto ya no ve lo que espera al administrador:
--
--   select polname from pg_policy
--   where polrelid = 'rutas'::regclass order by polname;
--
--   Tiene que estar "el runner experto ve las rutas pendientes de
--   su revision" y no "el runner experto ve las rutas en revision".
--
-- 2. Con la sesión de un usuario SIN rol de experto, aprobar una
--    ruta en `revision_experto` debe fallar con 42501.
--
-- 3. Y el registro queda:
--
--   select etapa, decision, motivo, revisor_nombre
--   from revisiones_ruta where ruta_id = '<RUTA>' order by fecha;
--
-- Para dejar la base limpia:
--
--   delete from revisiones_ruta where ruta_id = '<RUTA>';
--   update rutas set estado = 'en_revision', motivo_rechazo = null
--   where id = '<RUTA>';
-- -------------------------------------------------------------
