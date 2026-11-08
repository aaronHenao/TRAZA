-- =============================================================
-- TRAZA — Rutas oficiales, etapa 3 (docs/roadmap_mapa_rutas_oficiales.md)
--
-- El corredor puede salir a correr una ruta oficial desde su
-- detalle ("Correr esta ruta"). El entrenamiento recuerda qué
-- ruta se estaba corriendo, para que la etapa 4 compare sus puntos
-- GPS con el trazado de esa ruta.
--
-- Decisiones:
--
--   · Una columna anulable en `entrenamientos`: el entrenamiento
--     libre sigue siendo el caso normal y no cambia nada para él.
--
--   · La escribe el cliente al crear el entrenamiento, y solo con
--     una ruta que hoy es oficial: la policy de insert de 0056 se
--     rehace con esa condición. Así no se puede asociar una ruta
--     en revisión ni averiguar si existe un id ajeno.
--
--   · Después no se puede cambiar. Un trigger rechaza cualquier
--     cambio de `ruta_id` que no sea volver a null. Sin él, la
--     policy de update de 0056 dejaría reetiquetar un entrenamiento
--     viejo (o uno largo, varias veces) con la ruta que convenga y
--     completarla sin correrla. Volver a null sí se permite: es lo
--     que hace `on delete set null` si la ruta se borra.
--
--   · No da ventaja por sí sola: decir "corrí esta ruta" no la
--     completa. La etapa 4 no le cree al cliente; mira los puntos.
--
--   · Sin índice: nada busca entrenamientos por ruta. La etapa 4
--     llega al entrenamiento por su id.
--
--   · OJO para quien escriba consultas: desde aquí hay DOS
--     relaciones entre `entrenamientos` y `rutas`
--     (`rutas.entrenamiento_id`, de 0029, y esta). Un embed de
--     PostgREST entre las dos tablas tiene que nombrar la clave,
--     por ejemplo `rutas!entrenamientos_ruta_id_fkey(nombre)`, o
--     falla por ambiguo. Hoy la app no hace ninguno.
--
-- Corre esto DESPUÉS de 0059_rutas_completadas.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La columna
-- -------------------------------------------------------------
alter table entrenamientos
  add column ruta_id uuid references rutas(id) on delete set null;

comment on column entrenamientos.ruta_id is
  'La ruta oficial que se corrió en este entrenamiento (rutas oficiales, '
  'etapa 3), o null si fue libre. Se fija al crearlo y no cambia.';

-- -------------------------------------------------------------
-- 2. Solo con una ruta oficial, al crear
--
-- Solo en el insert: si el administrador quita la ruta del mapa
-- mientras alguien la corre, cerrar el entrenamiento (un update)
-- tiene que seguir funcionando.
-- -------------------------------------------------------------
drop policy "usuario registra sus propios entrenamientos" on entrenamientos;

create policy "usuario registra sus propios entrenamientos"
  on entrenamientos for insert
  with check (
    auth.uid() = usuario_id
    and (
      ruta_id is null
      or exists (
        select 1 from rutas_oficiales o where o.ruta_id = entrenamientos.ruta_id
      )
    )
  );

-- -------------------------------------------------------------
-- 3. La ruta no cambia después
-- -------------------------------------------------------------
create or replace function public.proteger_ruta_del_entrenamiento()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.ruta_id is distinct from old.ruta_id and new.ruta_id is not null then
    raise exception 'La ruta de un entrenamiento se fija al crearlo'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger entrenamientos_proteger_ruta
  before update of ruta_id on entrenamientos
  for each row execute function public.proteger_ruta_del_entrenamiento();

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un autor con dos rutas publicadas (una oficial y otra no)
-- y un corredor que sale a correr. Al final lanza un error A
-- PROPÓSITO para que todo se deshaga. El resultado es el mensaje
-- de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor     uuid := gen_random_uuid();
  v_corredor  uuid := gen_random_uuid();
  v_otro      uuid := gen_random_uuid();
  v_tipo      uuid := (select id from tipos_actividad limit 1);
  v_e1        uuid;
  v_e2        uuid;
  v_oficial   uuid;
  v_comun     uuid;
  v_libre     uuid;
  v_con_ruta  uuid;
  v_n         integer;
  v_trazado   jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                         {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor,    'prueba-entrenar-ruta-' || v_autor    || '@traza.test'),
    (v_corredor, 'prueba-entrenar-ruta-' || v_corredor || '@traza.test'),
    (v_otro,     'prueba-entrenar-ruta-' || v_otro     || '@traza.test');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 3000, 'finalizado') returning id into v_e1;
  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 4000, 'finalizado') returning id into v_e2;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e1, 'Ruta oficial', v_trazado) returning id into v_oficial;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e2, 'Ruta común', v_trazado) returning id into v_comun;

  -- Las dos publicadas; solo la primera entra al mapa.
  reset role;
  update rutas
    set estado = 'publicada', fecha_publicacion = now(), dificultad = 'facil'
    where id in (v_oficial, v_comun);
  insert into rutas_oficiales (ruta_id, posicion)
    select v_oficial, coalesce(max(posicion), 0) + 1 from rutas_oficiales;

  -- El corredor crea un entrenamiento libre, como hoy, y otro con la
  -- ruta oficial, como lo hace la app al tocar "Correr esta ruta".
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado)
    values (v_corredor, v_tipo, 'en_curso') returning id into v_libre;
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id)
    values (v_corredor, v_tipo, 'en_curso', v_oficial) returning id into v_con_ruta;

  select count(*) into v_n from entrenamientos
    where id = v_libre and ruta_id is null;
  if v_n <> 1 then raise exception 'FALLÓ: el entrenamiento libre quedó con ruta'; end if;
  select count(*) into v_n from entrenamientos
    where id = v_con_ruta and ruta_id = v_oficial;
  if v_n <> 1 then raise exception 'FALLÓ: el entrenamiento no recuerda su ruta'; end if;

  -- Solo una ruta oficial: ni una publicada que no lo es, ni un id
  -- que no existe (no se puede averiguar si existe).
  begin
    insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id)
      values (v_corredor, v_tipo, 'en_curso', v_comun);
    raise exception 'FALLÓ: se asoció una ruta que no es oficial';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into entrenamientos (usuario_id, tipo_actividad_id, estado, ruta_id)
      values (v_corredor, v_tipo, 'en_curso', gen_random_uuid());
    raise exception 'FALLÓ: se asoció una ruta que no existe';
  exception when insufficient_privilege then null;
  end;

  -- El dueño no reetiqueta: ni el libre con una ruta, ni el que tiene
  -- ruta con otra. Cerrar sigue funcionando.
  begin
    update entrenamientos set ruta_id = v_oficial where id = v_libre;
    raise exception 'FALLÓ: el dueño le puso ruta a un entrenamiento libre';
  exception when insufficient_privilege then null;
  end;
  begin
    update entrenamientos set ruta_id = v_comun where id = v_con_ruta;
    raise exception 'FALLÓ: el dueño cambió la ruta de su entrenamiento';
  exception when insufficient_privilege then null;
  end;
  update entrenamientos
    set estado = 'finalizado', fecha_fin = now(), duracion_segundos = 600
    where id = v_con_ruta;
  select count(*) into v_n from entrenamientos
    where id = v_con_ruta and estado = 'finalizado' and ruta_id = v_oficial;
  if v_n <> 1 then raise exception 'FALLÓ: no se pudo cerrar el entrenamiento con ruta'; end if;

  -- Si la ruta se borra, el entrenamiento queda libre y se conserva
  -- (el trigger deja volver a null).
  reset role;
  delete from rutas where id = v_oficial;
  select count(*) into v_n from entrenamientos
    where id = v_con_ruta and ruta_id is null;
  if v_n <> 1 then
    raise exception 'FALLÓ: al borrar la ruta, el entrenamiento no quedó libre';
  end if;

  raise exception 'VERIFICACIÓN OK: entrenamientos.ruta_id cumple la etapa 3 (todo se deshace)';
end;
$$;
*/
