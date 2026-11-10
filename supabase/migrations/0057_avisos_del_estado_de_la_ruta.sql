-- =============================================================
-- TRAZA — El autor sabe en todo momento dónde va su ruta
--
-- Publicar una ruta no es inmediato: pasa por el administrador y
-- después por un Runner Experto. De ese recorrido, al autor solo
-- se le avisaba del final:
--
--   crear            → en_revision        (sin aviso)   ← falta
--   admin aprueba    → revision_experto   (sin aviso)   ← falta
--   experto clasifica→ clasificada        0048, `ruta_clasificada`
--   cualquiera rechaza → rechazada        0044, `ruta_rechazada`
--   el autor confirma→ publicada          0033, `ruta_publicada`
--
-- Entre que la manda y que un experto la clasifica pueden pasar
-- días, y en ese hueco la app no le decía nada: la ruta
-- simplemente no aparecía. Esta migración añade los dos avisos
-- que faltan, para que cada cambio de etapa tenga el suyo.
--
-- Se hace con triggers sobre el estado, como 0033 y 0044, y no
-- metiendo el aviso dentro de `decidir_revision_ruta` (0048):
-- así no hay que recrear esa función —que decide las dos puertas
-- y es larga— para añadirle un aviso, y el aviso salta por el
-- cambio de estado, sea quien sea el que lo provoque.
--
-- Corre esto DESPUÉS de 0056_sin_delete_en_los_datos.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. Los dos tipos nuevos
--
-- La restricción se reemplaza entera, como hizo 0045 al añadir
-- `ruta_clasificada`. Los nombres dicen en qué etapa está, no
-- quién la movió: `ruta_en_revision` mientras la mira el
-- administrador y `ruta_en_clasificacion` mientras la mira el
-- experto.
--
-- `TipoNotificacion` (`lib/models/notificacion.dart`) tiene que
-- conocerlos o la bandeja los descarta en silencio: un tipo que
-- la app no sabe leer devuelve nulo y esa fila no se pinta. Van
-- en el mismo PR.
-- -------------------------------------------------------------
alter table notificaciones drop constraint notificaciones_tipo_valido;
alter table notificaciones
  add constraint notificaciones_tipo_valido
    check (tipo in (
      'ruta_publicada', 'ruta_rechazada', 'publicacion_retirada',
      'ruta_clasificada', 'ruta_en_revision', 'ruta_en_clasificacion'
    ));

-- -------------------------------------------------------------
-- 2. Al mandarla: la está mirando el administrador
--
-- `security definer` por lo mismo que 0033 y 0044:
-- `crear_notificacion()` no tiene permiso de ejecución para los
-- usuarios, y dentro de esta función el usuario en curso es su
-- dueño.
--
-- Solo cuando nace `en_revision`. Una ruta sin distancia nace
-- `datos_incompletos` (0045) y no la revisa nadie: decirle que
-- está en revisión sería mentirle. De eso ya le avisa la propia
-- pantalla al publicar.
-- -------------------------------------------------------------
create function public.avisar_ruta_en_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.crear_notificacion(
    new.autor_id,
    'ruta_en_revision',
    'Tu ruta está en revisión',
    format(
      'El administrador está revisando «%s». Te avisamos en cuanto '
      'haya novedades.',
      new.nombre
    ),
    new.id
  );

  return null;
end;
$$;

create trigger rutas_avisar_en_revision
  after insert on rutas
  for each row
  when (new.estado = 'en_revision')
  execute function public.avisar_ruta_en_revision();

-- -------------------------------------------------------------
-- 3. Aprobada por el administrador: ahora la clasifica un experto
--
-- El aviso dice qué va a pasar después —que le pongan dificultad—
-- porque para el autor eso es la novedad, no el trámite que se
-- cerró.
--
-- `old.estado <> new.estado` en el trigger, igual que 0033 y
-- 0044: si la fila se actualiza por cualquier otra cosa estando
-- ya en revisión del experto, no se vuelve a avisar.
-- -------------------------------------------------------------
create function public.avisar_ruta_en_clasificacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.crear_notificacion(
    new.autor_id,
    'ruta_en_clasificacion',
    'Tu ruta pasó la primera revisión',
    format(
      'El administrador aprobó «%s». Ahora un Runner Experto le pondrá '
      'la dificultad.',
      new.nombre
    ),
    new.id
  );

  return null;
end;
$$;

create trigger rutas_avisar_en_clasificacion
  after update on rutas
  for each row
  when (new.estado = 'revision_experto' and old.estado <> 'revision_experto')
  execute function public.avisar_ruta_en_clasificacion();

-- =============================================================
-- COMPROBACIÓN (correr después, en el SQL Editor, como un script
-- aparte)
--
-- Va entera dentro de una transacción que termina en ROLLBACK: no
-- deja ni la ruta de prueba ni los avisos.
--
-- Cambia <AUTOR> por un id de `auth.users` con perfil. Se corre
-- como `postgres`, que es el dueño y se salta RLS, así que no hay
-- que hacerse pasar por nadie: lo que se comprueba son los
-- triggers, que corren igual.
--
-- Devuelve UNA FILA POR PASO, no un `raise notice`: el editor de
-- Supabase no muestra los avisos, así que un guion que terminara
-- en `notice` diría "Success. No rows returned" tanto si pasa como
-- si falla, que es lo mismo que no decir nada.
--
-- Cada paso atrapa su propio error y lo escribe con su `sqlstate`
-- y su mensaje. Así, cuando algo se rompe, la tabla dice qué paso
-- fue y por qué, en vez de que Postgres señale el `$$` del bloque
-- y haya que adivinar.
--
-- Los cinco pasos tienen que decir "ok".
-- =============================================================
/*
begin;

create temp table veredicto_0057 (paso text, resultado text);

do $$
declare
  v_autor  uuid := '<AUTOR>';
  v_tipo   uuid;
  v_ent    uuid;
  v_ruta   uuid;
  v_n      integer;
begin
  -- 0. Lo que el guion necesita para empezar.
  select id into v_tipo from tipos_actividad limit 1;
  insert into veredicto_0057 values (
    '0 preparar',
    case
      when v_tipo is null then 'FALLO: tipos_actividad esta vacia'
      when not exists (select 1 from perfiles where id = v_autor)
        then 'FALLO: ese id no tiene perfil'
      else 'ok'
    end
  );
  if v_tipo is null then return; end if;

  -- 1. Una ruta con distancia nace en revision y avisa al autor.
  begin
    insert into entrenamientos
      (usuario_id, tipo_actividad_id, estado, distancia_total_m,
       duracion_segundos, fecha_fin)
    values (v_autor, v_tipo, 'finalizado', 5230, 1800, now())
    returning id into v_ent;

    insert into rutas (entrenamiento_id, autor_id, nombre, trazado)
    values (
      v_ent, v_autor, 'Ruta de prueba 0057',
      '[{"lat":6.2442,"lng":-75.5812},{"lat":6.2460,"lng":-75.5800}]'::jsonb
    )
    returning id into v_ruta;

    select count(*) into v_n from notificaciones
     where entidad_id = v_ruta and tipo = 'ruta_en_revision';

    insert into veredicto_0057 values (
      '1 aviso de revision',
      case when v_n = 1 then 'ok'
           else format('FALLO: %s avisos, esperaba 1', v_n) end
    );
  exception when others then
    insert into veredicto_0057 values (
      '1 aviso de revision', format('ERROR %s: %s', sqlstate, sqlerrm));
  end;

  if v_ruta is null then return; end if;

  -- 2. Al pasar al experto, el segundo aviso.
  begin
    update rutas set estado = 'revision_experto' where id = v_ruta;

    select count(*) into v_n from notificaciones
     where entidad_id = v_ruta and tipo = 'ruta_en_clasificacion';

    insert into veredicto_0057 values (
      '2 aviso de clasificacion',
      case when v_n = 1 then 'ok'
           else format('FALLO: %s avisos, esperaba 1', v_n) end
    );
  exception when others then
    insert into veredicto_0057 values (
      '2 aviso de clasificacion', format('ERROR %s: %s', sqlstate, sqlerrm));
  end;

  -- 3. Otro update estando ya con el experto no repite el aviso.
  begin
    update rutas set descripcion = 'tocada otra vez' where id = v_ruta;

    select count(*) into v_n from notificaciones
     where entidad_id = v_ruta and tipo = 'ruta_en_clasificacion';

    insert into veredicto_0057 values (
      '3 no se repite',
      case when v_n = 1 then 'ok'
           else format('FALLO: quedaron %s avisos', v_n) end
    );
  exception when others then
    insert into veredicto_0057 values (
      '3 no se repite', format('ERROR %s: %s', sqlstate, sqlerrm));
  end;

  -- 4. Una ruta sin distancia nace datos_incompletos y no avisa.
  begin
    insert into entrenamientos
      (usuario_id, tipo_actividad_id, estado, duracion_segundos, fecha_fin)
    values (v_autor, v_tipo, 'finalizado', 1800, now())
    returning id into v_ent;

    insert into rutas (entrenamiento_id, autor_id, nombre, trazado)
    values (
      v_ent, v_autor, 'Ruta sin distancia 0057',
      '[{"lat":6.2442,"lng":-75.5812},{"lat":6.2460,"lng":-75.5800}]'::jsonb
    )
    returning id into v_ruta;

    select count(*) into v_n from notificaciones where entidad_id = v_ruta;

    insert into veredicto_0057 values (
      '4 sin distancia no avisa',
      case when v_n = 0 then 'ok'
           else format('FALLO: genero %s avisos', v_n) end
    );
  exception when others then
    insert into veredicto_0057 values (
      '4 sin distancia no avisa', format('ERROR %s: %s', sqlstate, sqlerrm));
  end;
end
$$;

select paso, resultado from veredicto_0057 order by paso;

rollback;
*/

-- =============================================================
-- MARCHA ATRÁS (solo si hay que deshacer esta migración)
--
-- Quita los dos triggers y sus funciones, y devuelve la
-- restricción de 0045. El `delete` de los avisos ya creados es
-- obligatorio antes de estrechar la restricción: si queda alguna
-- fila con un tipo que el check nuevo no admite, el `add
-- constraint` falla.
-- =============================================================
/*
drop trigger rutas_avisar_en_revision on rutas;
drop trigger rutas_avisar_en_clasificacion on rutas;
drop function public.avisar_ruta_en_revision();
drop function public.avisar_ruta_en_clasificacion();

delete from notificaciones
 where tipo in ('ruta_en_revision', 'ruta_en_clasificacion');

alter table notificaciones drop constraint notificaciones_tipo_valido;
alter table notificaciones
  add constraint notificaciones_tipo_valido
    check (tipo in (
      'ruta_publicada', 'ruta_rechazada', 'publicacion_retirada',
      'ruta_clasificada'
    ));
*/
