-- =============================================================
-- TRAZA — RNF-04: si la ruta se publicó con el recorrido completo
--
-- Al publicar, la app recorta los primeros y los últimos 200 m
-- del recorrido para no delatar de dónde salió su autor
-- (`radioPrivacidadMetros`, lib/models/ruta.dart). Quien publica
-- puede desactivarlo con un interruptor y compartir el recorrido
-- entero.
--
-- El detalle de la ruta avisa "Trazo recortado por privacidad",
-- y solo debe decirlo cuando es verdad. Quien mira una ruta casi
-- nunca es su autor, así que no puede saberlo por su cuenta:
--
--   · `rutas.entrenamiento_id` es `on delete set null` (0029), así
--     que puede no haber entrenamiento con el que comparar.
--   · `puntos_gps` solo lo lee su dueño (RLS por join, 0001), así
--     que un extraño no podría comparar aunque lo hubiera.
--
-- Por eso la ruta tiene que recordar cómo se publicó.
--
-- **La columna es anulable a propósito**, no `not null default
-- false`. Las rutas publicadas antes de esto conservan sus
-- extremos exactos: con un `default false` pasarían a afirmar que
-- están recortadas, que es mentira. Con nulo no afirman nada y la
-- app no les pone la nota.
--
--   null  → no consta (rutas anteriores a RNF-04)
--   false → se recortó: el trazo no llega a los extremos reales
--   true  → su autor eligió publicar el recorrido completo
--
-- Corre esto DESPUÉS de 0054_revisar_clasificacion.sql.
-- =============================================================

alter table rutas
  add column recorrido_completo boolean;

comment on column rutas.recorrido_completo is
  'RNF-04: true si su autor publicó el recorrido entero, false si se '
  'recortaron los extremos, null si la ruta es anterior a esta función.';

-- -------------------------------------------------------------
-- Que no se pueda cambiar después de publicar
--
-- Hoy `rutas` no tiene ninguna policy de `update`: la app no
-- puede tocar la tabla y los cambios de estado pasan por
-- funciones `security definer`. Así que ahora mismo nadie puede
-- cambiarla.
--
-- Pero `proteger_ruta` (0046) congela una lista explícita de
-- columnas, y la nueva no estaría en ella: el día que alguien
-- añada una policy de update, el autor podría decir que su ruta
-- está recortada cuando no lo está. Se añade a la lista ahora,
-- que es barato, en vez de confiar en que nadie la añada.
--
-- Se recrea la función entera porque es lo que `create or
-- replace` exige; lo único nuevo es la línea de
-- `recorrido_completo`. La 0046 no se toca.
-- -------------------------------------------------------------
create or replace function public.proteger_ruta()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.autor_id := old.autor_id;
    new.autor_nombre := old.autor_nombre;
    new.entrenamiento_id := old.entrenamiento_id;
    new.trazado := old.trazado;
    new.inicio_latitud := old.inicio_latitud;
    new.inicio_longitud := old.inicio_longitud;
    new.distancia_km := old.distancia_km;
    new.estado := old.estado;
    new.dificultad := old.dificultad;
    new.clasificada_por := old.clasificada_por;
    new.motivo_rechazo := old.motivo_rechazo;
    new.fecha_creacion := old.fecha_creacion;
    new.fecha_publicacion := old.fecha_publicacion;
    -- RNF-04: cómo se publicó se decide una vez, al publicar.
    new.recorrido_completo := old.recorrido_completo;
  end if;
  return new;
end;
$$;

revoke execute on function public.proteger_ruta()
  from public, anon, authenticated;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Que la columna está y admite nulo:
--
--   select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--   where table_name = 'rutas' and column_name = 'recorrido_completo';
--
--   Tiene que decir boolean / YES / null. Si `is_nullable` dijera
--   NO, o hubiera un default, las rutas antiguas estarían
--   afirmando algo que no se sabe: eso es lo que se quería evitar.
--
-- 2. Que las rutas de antes quedaron en "no consta":
--
--   select count(*) as sin_constancia
--   from rutas
--   where recorrido_completo is null;
--
--   Debe ser el total de rutas que ya había.
--
-- 3. Que el trigger la congela. Con la sesión de un
--    administrador (ver la cabecera de suplantación de 0052):
--
--   select set_config('traza.moderando', 'off', true);
--   update rutas set recorrido_completo = true
--    where id = '<UNA RUTA>';
--
--   Si no hay policy de update, falla por permisos, que es lo
--   esperado hoy. Si algún día la hay, el valor no debe cambiar:
--
--   select recorrido_completo from rutas where id = '<UNA RUTA>';
--
-- 4. Que la app puede insertarla. Lo comprueba publicar una ruta
--    desde la app con el interruptor apagado y mirar:
--
--   select nombre, recorrido_completo
--   from rutas
--   order by fecha_creacion desc
--   limit 1;
--
--   Tiene que decir `false`. Con el interruptor encendido, `true`.
-- -------------------------------------------------------------
