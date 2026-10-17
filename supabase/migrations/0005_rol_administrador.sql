-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-137: rol de usuario
--
-- El administrador entra por el mismo login que los corredores,
-- con una cuenta única. Lo que lo distingue es esta columna.
--
-- Corre esto DESPUÉS de 0002_perfiles.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La columna
--
-- `not null` con default: los perfiles que ya existen quedan
-- como 'usuario' sin necesidad de un backfill aparte, y el
-- trigger `handle_new_user` sigue funcionando sin tocarlo —
-- inserta sin rol y el default se encarga.
-- -------------------------------------------------------------
alter table perfiles
  add column rol text not null default 'usuario';

alter table perfiles
  add constraint perfiles_rol_valido
    check (rol in ('usuario', 'admin'));

-- -------------------------------------------------------------
-- 2. es_admin(): quién puede administrar
--
-- Existe para usarla dentro de las policies de las tablas que
-- solo el administrador puede escribir (retos, en 0006).
--
-- `security definer` a propósito: la ejecuta el dueño de la
-- función, así que salta el RLS de `perfiles`. Sin eso, cada
-- policy que la llame dispararía otra consulta sujeta a RLS
-- sobre la misma tabla.
--
-- `stable` porque dentro de una misma sentencia el rol no
-- cambia: Postgres puede evaluarla una vez en vez de por fila.
-- -------------------------------------------------------------
create function public.es_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and rol = 'admin'
  );
$$;

-- -------------------------------------------------------------
-- 3. El perfil de esa cuenta única
--
-- ⚠️ CAMBIA EL CORREO por el de la cuenta de administrador
--    ANTES de correr este script. Esa cuenta tiene que estar
--    ya registrada en la app: el rol se asigna sobre un perfil
--    que existe, no crea la cuenta.
--
-- Si el correo no coincide con ninguna cuenta, esto no falla:
-- simplemente no actualiza nada y el rol se puede asignar
-- después repitiendo solo este update.
-- -------------------------------------------------------------
update perfiles
set rol = 'admin'
where id = (
  select id from auth.users
  where lower(email) = lower('davidadmin@traza.app')
);
