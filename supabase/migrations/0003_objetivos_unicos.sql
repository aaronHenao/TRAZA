-- =============================================================
-- TRAZA — objetivos: un solo objetivo por tipo y por usuario
-- Corre esto DESPUÉS de 0001_init_sprint1.sql
--
-- Sin esta restricción el cliente no puede hacer upsert, así que para guardar
-- tenía que borrar todos los objetivos del usuario y volver a insertarlos. Si
-- el insert fallaba después del delete, el usuario se quedaba sin objetivos.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Quitar duplicados que hayan quedado antes de la restricción,
--    conservando el más reciente de cada (usuario_id, tipo).
-- -------------------------------------------------------------
delete from objetivos
where id in (
  select id
  from (
    select
      id,
      row_number() over (
        partition by usuario_id, tipo
        order by fecha_creacion desc, id desc
      ) as fila
    from objetivos
  ) duplicados
  where fila > 1
);

-- -------------------------------------------------------------
-- 2. La restricción. Es la que habilita el `on conflict` del upsert.
-- -------------------------------------------------------------
alter table objetivos
  add constraint objetivos_usuario_tipo_unico unique (usuario_id, tipo);
