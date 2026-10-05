-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-229: anuncio del rol desbloqueado
--
-- `roles_usuario` (0011) guarda `anunciado_en` para distinguir
-- "lo acaba de desbloquear" de "ya lo sabe". Falta cómo se
-- marca: esta migración lo resuelve.
--
-- Decisiones:
--   - Una función y no una policy de update. Con un update
--     abierto, el cliente podría cambiar `rol` u `otorgado_en`
--     de sus propias filas; habría que impedirlo con otro
--     trigger. Con esta función, lo único que puede hacer es
--     marcar el anuncio, y la tabla sigue sin escritura directa.
--   - `anunciado_en is null` en el where: la fecha se escribe
--     una sola vez. Volver a llamarla no la mueve, así que el
--     aviso no reaparece (criterio 5 de SCRUM-224).
--   - Sin parámetro de usuario: siempre es el de la sesión. Así
--     nadie puede marcar el anuncio de otra cuenta.
--
-- Corre esto DESPUÉS de 0011_roles_usuario.sql.
-- =============================================================

create function public.marcar_rol_anunciado(p_rol text)
returns void
language sql
security definer set search_path = public
as $$
  update roles_usuario
  set anunciado_en = now()
  where usuario_id = auth.uid()
    and rol = p_rol
    and anunciado_en is null;
$$;

-- La llama la app con la sesión del usuario; `anon` no tiene
-- nada que marcar.
revoke execute on function public.marcar_rol_anunciado(text)
  from public, anon;
grant execute on function public.marcar_rol_anunciado(text)
  to authenticated;

-- -------------------------------------------------------------
-- Comprobación
--
-- Para correr en el SQL Editor después de aplicar la migración.
-- Con una sesión abierta no falla aunque no haya nada que
-- marcar: actualiza cero filas.
-- -------------------------------------------------------------
-- select public.marcar_rol_anunciado('experto');
-- select rol, otorgado_en, anunciado_en from roles_usuario;
