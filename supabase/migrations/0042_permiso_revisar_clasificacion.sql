-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-260 (HU-35): quién puede revisar la
-- clasificación de una ruta
--
-- HU-35 (SCRUM-259) deja que un Runner Experto revise la
-- dificultad de una ruta para confirmarla o corregirla. Esta
-- migración pone en la base la regla de QUIÉN puede hacerlo:
--
--   · Tiene el rol de Runner Experto. Es el que entrega el
--     desbloqueo del rol (SCRUM-224): se gana corriendo (0012) y
--     vive en `roles_usuario` (0011), donde el cliente no escribe.
--     Lo consulta `es_experto()`, la misma que ya usan las
--     policies de rutas (0029).
--
--   · No es el autor de la ruta. Nadie revisa la clasificación de
--     lo que él mismo publicó: la revisión existe para que la
--     comunidad vea una clasificación confiable (HU-35).
--
-- Decisiones:
--
--   · Una función y no una policy suelta. La van a usar la policy
--     de la dificultad, la función que guarde la revisión y la app
--     para decidir qué mostrar (criterio 1 de HU-35): la regla
--     vive en un solo lugar y nadie la tiene que repetir.
--
--   · `security definer`, como `es_experto()` y `es_admin()`: mira
--     el autor de la ruta sin depender de las policies de select,
--     que dejan ver unas rutas a unos y otras a otros. `stable`,
--     porque dentro de una sentencia no cambia. Solo responde sí o
--     no: no devuelve nada de la ruta.
--
--   · El administrador no revisa por serlo. HU-35 se lo da al
--     Runner Experto ("un usuario sin el rol de Runner Experto no
--     puede revisar clasificaciones"). Un administrador que además
--     se haya ganado el rol, sí.
--
--   · Solo con sesión, como las consultas de rutas (0040): se le
--     quita a `public` y a `anon`, que en Supabase no pierde nada
--     por quitárselo solo a `public`.
--
-- Lo que NO hace esta migración:
--
--   · No crea la dificultad ni dice cuándo se revisa. La columna
--     `rutas.dificultad` es de SCRUM-363, y la revisión del Runner
--     Experto dentro de la publicación, de SCRUM-321. Los permisos
--     sobre ese dato —quién lo cambia y en qué estado de la ruta—
--     se escriben encima de esta función cuando existan, en otra
--     migración.
--
--   · No toca ninguna tabla.
--
-- Corre esto DESPUÉS de 0011_roles_usuario.sql y de
-- 0029_rutas.sql.
-- =============================================================

begin;

create function public.puede_revisar_clasificacion(p_ruta_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.es_experto()
    and exists (
      select 1 from public.rutas
      where id = p_ruta_id
        -- Sin sesión, `auth.uid()` es nulo y la comparación no da
        -- verdadero: también por aquí la respuesta es no.
        and autor_id <> auth.uid()
    );
$$;

comment on function public.puede_revisar_clasificacion(uuid) is
  'Si quien llama puede revisar la clasificación de la ruta '
  '(SCRUM-260, HU-35): tiene el rol de Runner Experto y no es su '
  'autor.';

revoke all on function public.puede_revisar_clasificacion(uuid)
  from public, anon;
grant execute on function public.puede_revisar_clasificacion(uuid)
  to authenticated;

commit;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. El SQL Editor corre sin usuario, así que nadie es Runner
--    Experto: con cualquier ruta tiene que dar `false`, sin error.
--
--   select public.puede_revisar_clasificacion(id) from rutas limit 1;
--
-- 2. Sin sesión no se puede llamar; con sesión, sí. Tiene que dar
--    `false` y `true`:
--
--   select
--     has_function_privilege('anon',
--       'public.puede_revisar_clasificacion(uuid)', 'execute') as sin_sesion,
--     has_function_privilege('authenticated',
--       'public.puede_revisar_clasificacion(uuid)', 'execute') as con_sesion;
--
-- 3. Que diga que sí a un Runner Experto y que no a su autor se
--    prueba con una sesión de verdad, desde la app: el SQL Editor
--    no tiene usuario.
-- -------------------------------------------------------------
