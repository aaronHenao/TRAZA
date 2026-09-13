-- =============================================================
-- TRAZA — Datos físicos del perfil
--
-- Los recoge el onboarding, no el registro. Por eso todas las
-- columnas son nullable: la cuenta existe desde el primer
-- momento, aunque el usuario no complete el onboarding.
-- =============================================================

alter table perfiles
  add column peso_kg          numeric,
  add column altura_cm        numeric,
  add column fecha_nacimiento date,
  add column genero           text;

-- -------------------------------------------------------------
-- Restricciones de rango
--
-- Van como constraints separados y con nombre para que, cuando
-- uno falle, el error diga cuál fue. Se escriben como "es nulo
-- O está en rango" porque un check con NULL no se evalúa a
-- verdadero, y sin el "is null" bloquearía a los perfiles que
-- todavía no completaron el onboarding.
-- -------------------------------------------------------------
alter table perfiles
  add constraint perfiles_peso_valido
    check (peso_kg is null or (peso_kg > 0 and peso_kg < 500)),

  add constraint perfiles_altura_valida
    check (altura_cm is null or (altura_cm > 0 and altura_cm < 300)),

  add constraint perfiles_fecha_nacimiento_valida
    check (fecha_nacimiento is null or fecha_nacimiento < current_date),

  add constraint perfiles_genero_valido
    check (genero is null or genero in (
      'masculino', 'femenino', 'otro', 'prefiero_no_decir'
    ));

-- -------------------------------------------------------------
-- RLS: no hace falta tocar nada.
--
-- La política "usuario ve y edita su propio perfil" de
-- 0002_perfiles.sql es 'for all' sobre la tabla completa, así
-- que cubre las columnas nuevas automáticamente.
-- -------------------------------------------------------------
