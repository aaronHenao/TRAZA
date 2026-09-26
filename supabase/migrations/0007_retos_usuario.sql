-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-136: retos activados por cada usuario
--
-- Es la relación entre un corredor y un reto del catálogo: cuándo
-- lo activó, cuánto lleva y si lo completó.
--
-- Se adelanta a la implementación de SCRUM-136 porque es lo que
-- necesita la historia de ganancia de experiencia para tener a
-- qué acreditar la XP.
--
-- Corre esto DESPUÉS de 0006_retos.sql.
-- =============================================================

create table retos_usuario (
  id                  uuid primary key default gen_random_uuid(),
  usuario_id          uuid not null references auth.users(id) on delete cascade,
  -- Sin `on delete cascade`: un reto no se borra, se retira
  -- (0006_retos.sql no tiene policy de delete). Si algún día se
  -- borrara desde el dashboard, esto lo impediría en vez de
  -- llevarse por delante el historial de los corredores.
  reto_id             uuid not null references retos(id),
  estado              text not null default 'en_progreso',
  -- Lo que lleva acumulado hacia la meta del reto. Arranca en
  -- cero: activar no es haber corrido nada todavía.
  progreso_km         numeric not null default 0,
  fecha_activacion    timestamptz not null default now(),
  -- Cuándo lo completó. Nulo mientras siga en progreso.
  fecha_completado    timestamptz,

  -- SCRUM-169: un reto no se puede activar dos veces. La
  -- restricción es lo que hace que la regla se cumpla aunque dos
  -- toques lleguen a la vez.
  unique (usuario_id, reto_id)
);

alter table retos_usuario
  add constraint retos_usuario_estado_valido
    check (estado in ('en_progreso', 'completado', 'vencido')),

  add constraint retos_usuario_progreso_no_negativo
    check (progreso_km >= 0),

  -- Completado y sin fecha, o con fecha y sin completar, serían
  -- filas que se contradicen a sí mismas.
  add constraint retos_usuario_completado_con_fecha
    check (
      (estado = 'completado' and fecha_completado is not null)
      or (estado <> 'completado' and fecha_completado is null)
    );

-- -------------------------------------------------------------
-- Índice
--
-- La consulta que va a existir siempre es "los retos de este
-- usuario", para marcar en el catálogo los que ya activó.
-- -------------------------------------------------------------
create index retos_usuario_por_usuario_idx
  on retos_usuario (usuario_id, estado);

-- -------------------------------------------------------------
-- RLS
-- -------------------------------------------------------------
alter table retos_usuario enable row level security;

-- Cada corredor gestiona lo suyo y solo lo suyo.
create policy "usuario gestiona sus propios retos"
  on retos_usuario
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- El administrador los lee, sin poder tocarlos.
--
-- Lo necesita para saber cuántos corredores tiene un reto en
-- progreso: SCRUM-133 avisa antes de cambiar la meta o la XP, y
-- SCRUM-134 antes de retirarlo. Solo lectura a propósito: el
-- progreso es del corredor, no del administrador.
create policy "el administrador ve el progreso de los retos"
  on retos_usuario
  for select
  using (public.es_admin());

-- -------------------------------------------------------------
-- Nota para la historia de ganancia de experiencia
--
-- Aquí no hay columna de XP acreditada. Cuánta XP tiene un
-- usuario y cómo se le suma es de esa historia, y su migración
-- decidirá si va en `perfiles`, en una tabla de movimientos o en
-- otra parte. Lo que esta tabla garantiza es lo que esa historia
-- necesita saber: qué reto completó cada corredor y cuándo.
-- -------------------------------------------------------------
