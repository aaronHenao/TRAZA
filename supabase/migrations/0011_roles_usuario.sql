-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-225: roles que se ganan
--
-- Hasta ahora el rol era uno solo: `perfiles.rol`, con 'usuario'
-- o 'admin' (0005). Eso sirve para el administrador, que es un
-- tipo de cuenta y se asigna a mano, pero no para Runner
-- Experto, que se desbloquea corriendo y convive con el rol que
-- la cuenta ya tenga.
--
-- Decisiones:
--   - Tabla aparte en vez de otro valor de `perfiles.rol`: los
--     roles ganados se suman, no se reemplazan. Así `es_admin()`
--     y todo lo que depende de él siguen igual.
--   - Una fila por rol ganado, con `unique (usuario_id, rol)`.
--     Esa restricción es el criterio 5 de SCRUM-224 —asignación
--     única— puesto donde no se puede saltar, aunque dos
--     verificaciones lleguen a la vez.
--   - `anunciado_en` vive aquí y no en la app: si el aviso se
--     guardara en el dispositivo, cambiar de teléfono volvería a
--     anunciar un rol viejo.
--   - El cliente no escribe en esta tabla. Quién otorga el rol y
--     con qué requisitos es otra subtarea, y será la base la que
--     lo haga, como con la XP (0009) y las insignias (0010).
--
-- Corre esto DESPUÉS de 0005_rol_administrador.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La tabla
-- -------------------------------------------------------------
create table roles_usuario (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid not null references auth.users(id) on delete cascade,
  rol           text not null,
  otorgado_en   timestamptz not null default now(),
  -- Cuándo se le avisó al usuario. Nulo mientras no se le haya
  -- anunciado: es lo que distingue "lo acaba de desbloquear" de
  -- "ya lo sabe" (criterio 2 de SCRUM-224).
  anunciado_en  timestamptz,

  -- Un rol se tiene una vez. Volver a cumplir la condición no
  -- crea otra fila ni cambia `otorgado_en`, así que tampoco se
  -- vuelve a anunciar (criterio 5).
  constraint roles_usuario_una_vez unique (usuario_id, rol)
);

-- Los roles que se ganan. 'usuario' y 'admin' no están: esos son
-- el tipo de cuenta y siguen en `perfiles.rol`. Añadir uno nuevo
-- es otra migración, a propósito: cada rol trae permisos.
alter table roles_usuario
  add constraint roles_usuario_rol_valido
    check (rol in ('experto')),

  -- Anunciar algo antes de otorgarlo sería una fila que se
  -- contradice a sí misma.
  add constraint roles_usuario_anuncio_despues_de_otorgar
    check (anunciado_en is null or anunciado_en >= otorgado_en);

-- -------------------------------------------------------------
-- 2. RLS
--
-- Solo lectura desde el cliente. Sin policies de insert ni de
-- delete: los roles los otorga la base y no se quitan solos.
-- Marcar el anuncio llega con la subtarea de la notificación.
-- -------------------------------------------------------------
alter table roles_usuario enable row level security;

create policy "usuario ve sus propios roles"
  on roles_usuario
  for select
  using (auth.uid() = usuario_id);

-- El administrador los lee para saber quién desbloqueó qué, sin
-- poder tocarlos: el rol se gana corriendo, no se regala.
create policy "el administrador ve los roles de todos"
  on roles_usuario
  for select
  using (public.es_admin());

-- -------------------------------------------------------------
-- 3. es_experto(): quién tiene el rol
--
-- La gemela de `es_admin()` (0005), para usarla dentro de las
-- policies de lo que solo el Runner Experto puede hacer. La
-- interfaz decide qué muestra, pero quien impide la acción es
-- esto (criterio 4 de SCRUM-224).
--
-- `security definer` por lo mismo que `es_admin()`: la ejecuta
-- el dueño de la función y así no dispara otra consulta sujeta a
-- RLS sobre la misma tabla. `stable`, porque dentro de una
-- sentencia el rol no cambia.
-- -------------------------------------------------------------
create function public.es_experto()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.roles_usuario
    where usuario_id = auth.uid() and rol = 'experto'
  );
$$;

-- -------------------------------------------------------------
-- 4. Comprobación
--
-- Para correr en el SQL Editor después de aplicar la migración.
-- Con una sesión abierta devuelve false (nadie es experto
-- todavía); lo que importa es que responda sin error.
-- -------------------------------------------------------------
-- select public.es_experto();
