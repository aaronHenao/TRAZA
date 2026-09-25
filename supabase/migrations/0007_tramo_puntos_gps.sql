-- =============================================================
-- TRAZA — Tramo de cada punto GPS (BUG-005, SCRUM-116)
--
-- Lo que se recorre entre dos pausas es un tramo. Sin esta
-- columna el resumen une con una recta el punto donde se pausó
-- con el punto donde se reanudó.
--
-- 0 es el primer tramo; cada reanudación suma 1. Con default 0,
-- los puntos ya guardados y los que envíe una versión anterior
-- de la app quedan como un solo tramo, igual que antes.
--
-- Aplicar ANTES de desplegar la app que envía y lee `tramo`: sin
-- la columna, el insert del lote y la lectura del resumen fallan.
-- =============================================================

alter table puntos_gps
  add column tramo smallint not null default 0;

alter table puntos_gps
  add constraint puntos_gps_tramo_no_negativo check (tramo >= 0);
