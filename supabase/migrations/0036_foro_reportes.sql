-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-369: reportar publicaciones del foro
--
-- Un corredor reporta una publicación que considera ofensiva,
-- con el motivo, y el reporte llega a la bandeja del
-- administrador (criterio 1).
--
-- Decisiones:
--
--   · Tabla propia y no `moderaciones_foro` (0035). Aquella es la
--     cola de lo que alguien escribe y su veredicto; un reporte es
--     la opinión de un tercero sobre algo ya publicado, y una
--     publicación puede tener muchos. Mezclarlos ensuciaría las
--     faltas de cada autor, que salen de esa tabla.
--
--   · La identidad del reportante no sale de aquí (criterio 2).
--     El autor no tiene ninguna policy sobre esta tabla, así que
--     ni sabe que lo reportaron. La app tampoco le pide
--     `reportante_id` al leer la bandeja del administrador.
--
--   · Un reporte por usuario y publicación (criterio 3) lo impide
--     el `unique`, no la app: con la publishable key cualquiera
--     puede llamar a la API. La app traduce el `23505` a "ya está
--     en revisión".
--
--   · Solo se reporta lo `publicada` y ajeno. Lo que espera la
--     moderación ya lo está revisando alguien, y reportarse a uno
--     mismo no tiene sentido.
--
--   · La fecha la pone la base. La bandeja del administrador se
--     ordena por ella y trae un número limitado de filas: con una
--     fecha futura, unos cuantos reportes falsos quedarían siempre
--     arriba y taparían los de verdad.
--
--   · Sin update ni delete: un reporte no se edita ni se retira.
--     Qué hace el administrador con lo reportado (eliminar la
--     publicación) es de SCRUM-242.
--
-- Corre esto DESPUÉS de 0035_foro_moderacion_ia.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La tabla
-- -------------------------------------------------------------
create table reportes_foro (
  id              uuid primary key default gen_random_uuid(),
  -- Si la publicación se borra, sus reportes ya no tienen qué
  -- señalar.
  publicacion_id  uuid not null references publicaciones_foro(id) on delete cascade,
  reportante_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  -- Los valores son los de `MotivoReporte` en
  -- `lib/models/reporte_foro.dart`: si cambia uno, cambia en los
  -- dos lados.
  motivo          text not null,
  detalle         text,
  fecha           timestamptz not null default now(),

  constraint reportes_foro_motivo_valido
    check (motivo in ('odio', 'acoso', 'contenido_sexual', 'violencia', 'spam', 'otro')),
  constraint reportes_foro_detalle_largo
    check (detalle is null or char_length(detalle) <= 280),
  -- "Otro" sin explicación no le dice nada al administrador.
  constraint reportes_foro_otro_con_detalle
    check (motivo <> 'otro' or char_length(btrim(coalesce(detalle, ''))) > 0),
  constraint reportes_foro_uno_por_usuario
    unique (publicacion_id, reportante_id)
);

-- La bandeja del administrador, lo más reciente primero. El
-- `unique` ya indexa (publicacion_id, reportante_id).
create index reportes_foro_fecha_idx
  on reportes_foro (fecha desc);

-- "Mis reportes" de la policy de select.
create index reportes_foro_reportante_idx
  on reportes_foro (reportante_id);

-- -------------------------------------------------------------
-- 2. La fecha la sella la base
--
-- Como `fecha_creacion` en `publicaciones_foro` (0020): el
-- cliente no la elige. `reportante_id` no se toca aquí: si lo
-- mandan con el id de otro, la policy de insert lo rechaza.
-- -------------------------------------------------------------
create function public.preparar_reporte_foro()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.fecha := now();
  return new;
end;
$$;

create trigger reportes_foro_preparar
  before insert on reportes_foro
  for each row execute function public.preparar_reporte_foro();

-- -------------------------------------------------------------
-- 3. RLS
-- -------------------------------------------------------------
alter table reportes_foro enable row level security;

-- Reportar: a su nombre, lo publicado y ajeno. La subconsulta
-- corre con el RLS de `publicaciones_foro`, que al corredor solo
-- le deja ver lo publicado y lo suyo.
create policy "el usuario reporta a su nombre lo publicado ajeno"
  on reportes_foro for insert
  to authenticated
  with check (
    auth.uid() = reportante_id
    and exists (
      select 1
      from publicaciones_foro p
      where p.id = reportes_foro.publicacion_id
        and p.estado = 'publicada'
        and p.autor_id <> auth.uid()
    )
  );

-- El reportante ve lo que él reportó; nadie más que el
-- administrador ve los reportes ajenos. El autor de la
-- publicación no tiene policy: no ve nada.
create policy "el usuario ve sus propios reportes"
  on reportes_foro for select
  to authenticated
  using (auth.uid() = reportante_id);

create policy "el administrador ve todos los reportes"
  on reportes_foro for select
  to authenticated
  using (public.es_admin());

-- Sin policies de update ni de delete, a propósito.

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un autor, dos corredores y un administrador de prueba, y
-- revisa los criterios 1 a 3 y el RLS. Al final lanza un error A
-- PROPÓSITO para que todo se deshaga: no deja nada en la base.
-- Tampoco llega a avisar a la moderación con IA: pg_net solo
-- manda lo que se confirma. El resultado es el mensaje de ese
-- error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor      uuid := gen_random_uuid();
  v_corredor   uuid := gen_random_uuid();
  v_otro       uuid := gen_random_uuid();
  v_admin      uuid := gen_random_uuid();
  v_publicada  uuid;
  v_revision   uuid;
  v_n          integer;
begin
  insert into auth.users (id, email) values
    (v_autor,    'prueba-reportes-' || v_autor    || '@traza.test'),
    (v_corredor, 'prueba-reportes-' || v_corredor || '@traza.test'),
    (v_otro,     'prueba-reportes-' || v_otro     || '@traza.test'),
    (v_admin,    'prueba-reportes-' || v_admin    || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;

  -- Una publicación publicada y otra que sigue en revisión. El
  -- estado solo cambia anunciando `traza.moderando`, como hace
  -- `resolver_moderacion` (0035).
  insert into publicaciones_foro (autor_id, titulo, contenido)
    values (v_autor, 'Publicada', 'Se puede reportar') returning id into v_publicada;
  insert into publicaciones_foro (autor_id, titulo, contenido)
    values (v_autor, 'En revisión', 'Todavía no') returning id into v_revision;
  perform set_config('traza.moderando', 'on', true);
  update publicaciones_foro set estado = 'publicada' where id = v_publicada;
  perform set_config('traza.moderando', 'off', true);

  -- Criterio 1: el corredor reporta lo publicado y ajeno. Manda
  -- una fecha futura para colarse arriba en la bandeja: la base la
  -- cambia por la de ahora.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into reportes_foro (publicacion_id, reportante_id, motivo, fecha)
    values (v_publicada, v_corredor, 'acoso', '2999-01-01');
  select count(*) into v_n from reportes_foro where publicacion_id = v_publicada;
  if v_n <> 1 then raise exception 'FALLÓ criterio 1: el corredor ve % reportes suyos, esperaba 1', v_n; end if;
  select count(*) into v_n from reportes_foro
    where publicacion_id = v_publicada and fecha > now();
  if v_n <> 0 then raise exception 'FALLÓ fecha: el cliente eligió la fecha del reporte'; end if;

  -- Criterio 3: el mismo corredor no la reporta dos veces.
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo)
      values (v_publicada, v_corredor, 'spam');
    raise exception 'FALLÓ criterio 3: se registró un segundo reporte del mismo usuario';
  exception when unique_violation then
    null; -- esperado (23505)
  end;
  select count(*) into v_n from reportes_foro where reportante_id = v_corredor;
  if v_n <> 1 then raise exception 'FALLÓ criterio 3: el corredor tiene % reportes, esperaba 1', v_n; end if;

  -- No se reporta a nombre de otro.
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo)
      values (v_publicada, v_otro, 'spam');
    raise exception 'FALLÓ RLS: el corredor reportó a nombre de otro usuario';
  exception when insufficient_privilege then
    null; -- esperado (42501)
  end;

  -- Ni lo que sigue en revisión.
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo)
      values (v_revision, v_corredor, 'spam');
    raise exception 'FALLÓ RLS: se reportó una publicación que no está publicada';
  exception when insufficient_privilege then
    null; -- esperado
  end;

  -- Un reporte no se edita ni se borra. En update y delete RLS no
  -- da error: deja 0 filas.
  begin
    update reportes_foro set motivo = 'spam' where reportante_id = v_corredor;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor editó % reportes', v_n; end if;
  begin
    delete from reportes_foro where reportante_id = v_corredor;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor borró % reportes', v_n; end if;

  -- Otro corredor reporta la misma publicación: sí puede, y no ve
  -- el reporte del primero.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);

  -- "Otro" sin detalle no pasa.
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo, detalle)
      values (v_publicada, v_otro, 'otro', '   ');
    raise exception 'FALLÓ check: se aceptó "otro" sin detalle';
  exception when check_violation then
    null; -- esperado (23514)
  end;

  -- Ni un detalle de más de 280 caracteres, ni un motivo que no
  -- está en la lista.
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo, detalle)
      values (v_publicada, v_otro, 'spam', repeat('a', 281));
    raise exception 'FALLÓ check: se aceptó un detalle de 281 caracteres';
  exception when check_violation then
    null; -- esperado
  end;
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo)
      values (v_publicada, v_otro, 'grosero');
    raise exception 'FALLÓ check: se aceptó un motivo que no existe';
  exception when check_violation then
    null; -- esperado
  end;

  insert into reportes_foro (publicacion_id, reportante_id, motivo, detalle)
    values (v_publicada, v_otro, 'otro', 'Se burla de otro corredor');
  select count(*) into v_n from reportes_foro where publicacion_id = v_publicada;
  if v_n <> 1 then raise exception 'FALLÓ RLS: un corredor ve % reportes de la publicación, esperaba solo el suyo', v_n; end if;

  -- Criterio 2: el autor no ve ningún reporte de lo suyo, ni
  -- puede reportarse a sí mismo.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  select count(*) into v_n from reportes_foro;
  if v_n <> 0 then raise exception 'FALLÓ criterio 2: el autor ve % reportes', v_n; end if;
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo)
      values (v_publicada, v_autor, 'spam');
    raise exception 'FALLÓ RLS: el autor reportó su propia publicación';
  exception when insufficient_privilege then
    null; -- esperado
  end;

  -- Criterio 1: los dos reportes llegan a la bandeja del
  -- administrador.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  select count(*) into v_n from reportes_foro where publicacion_id = v_publicada;
  if v_n <> 2 then raise exception 'FALLÓ criterio 1: el administrador ve % reportes, esperaba 2', v_n; end if;

  -- Sin sesión (anon) no se ve ni se reporta nada.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
  begin
    select count(*) into v_n from reportes_foro;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: sin sesión se ven % reportes', v_n; end if;
  begin
    insert into reportes_foro (publicacion_id, reportante_id, motivo)
      values (v_publicada, v_otro, 'spam');
    raise exception 'FALLÓ RLS: sin sesión se registró un reporte';
  exception when insufficient_privilege then
    null; -- esperado: no tiene policy de insert
  end;

  reset role;

  raise exception 'VERIFICACIÓN OK: criterios 1 a 3, fecha de la base, checks y RLS de reportes_foro. (Este error deshace los datos de prueba.)';
end;
$$;
*/
