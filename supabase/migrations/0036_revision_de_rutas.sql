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
