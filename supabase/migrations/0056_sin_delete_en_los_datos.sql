-- =============================================================
-- TRAZA — RNF-14: que nadie pueda borrar el historial ni la XP
--
-- Cinco tablas tenían una policy `for all`, y `for all` incluye
-- DELETE. Con eso, y con el privilegio DELETE que Supabase da por
-- defecto a `anon` y `authenticated`, el dueño de un entrenamiento
-- podía borrarlo. Y borrarlo se lleva por delante:
--
--   · `puntos_gps`         on delete cascade (0001)  → su traza
--   · `experiencia_ganada` on delete cascade (0009)  → su XP
--
-- Y `experiencia_total()` (0009) es un `sum(cantidad)` en vivo
-- sobre `experiencia_ganada`: al borrar un entrenamiento **baja la
-- XP total del usuario**, y con ella su nivel. Las insignias y el
-- rol ya concedidos son filas propias y no se revocan, así que
-- quedaría alguien con la insignia de 500 XP y menos de 500 XP.
-- No hay ningún trigger de delete que lo impida ni lo compense.
--
-- Esta migración cierra la puerta por los dos lados:
--
--   A. Parte cada `for all` en las operaciones que la app usa de
--      verdad. Queda escrito en la policy, que es donde este
--      proyecto documenta la autorización.
--   B. Quita el privilegio DELETE a `anon` y `authenticated` en
--      esas tablas. Es el cinturón: si mañana alguien escribe otra
--      policy `for all` sin pensarlo, el privilegio ya no está.
--
-- Lo que la app hace con cada tabla, medido sobre `lib/`:
--
--   entrenamientos    insert, update, select
--   puntos_gps        insert, select            ← ojo, sin update
--   permisos_usuario  insert, update, select
--   objetivos         insert, update, select, DELETE (legítimo)
--   perfiles          insert, update, select
--
-- **No se tocan las cascadas.** Que borrar un entrenamiento se
-- lleve la XP sigue siendo cierto en el esquema; lo que cambia es
-- que ya nadie puede borrarlo desde la app. Arreglar la cascada
-- sería cambiar el esquema de otra historia.
--
-- Corre esto DESPUÉS de 0055_recorrido_completo_de_la_ruta.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. entrenamientos
--
-- El historial. Se crea al iniciar, se actualiza al finalizar y al
-- cancelar, y se lee en el resumen y en el historial. Cancelar es
-- un `update estado = 'cancelado'`, no un borrado: por eso no hace
-- falta DELETE para descartar una actividad.
-- -------------------------------------------------------------
drop policy "usuario gestiona sus propios entrenamientos" on entrenamientos;

create policy "usuario ve sus propios entrenamientos"
  on entrenamientos for select
  using (auth.uid() = usuario_id);

create policy "usuario registra sus propios entrenamientos"
  on entrenamientos for insert
  with check (auth.uid() = usuario_id);

create policy "usuario actualiza sus propios entrenamientos"
  on entrenamientos for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 2. puntos_gps
--
-- No tiene `usuario_id`: se valida por join contra el
-- entrenamiento dueño, igual que antes.
--
-- **Sin policy de update, a propósito.** La app manda los lotes
-- con `on conflict do nothing` (`ignoreDuplicates`, SCRUM-292), que
-- no actualiza ninguna fila: solo necesita insertar. Si alguna vez
-- se quita ese `ignoreDuplicates` de `guardarLote`, el reenvío
-- empezará a fallar con 42501 y hará falta añadir aquí una policy
-- de update. Está dicho aquí porque las pruebas no lo verían: usan
-- dobles, no la base.
-- -------------------------------------------------------------
drop policy "usuario gestiona los puntos de sus propios entrenamientos"
  on puntos_gps;

create policy "usuario ve los puntos de sus propios entrenamientos"
  on puntos_gps for select
  using (
    exists (
      select 1 from entrenamientos e
      where e.id = puntos_gps.entrenamiento_id
        and e.usuario_id = auth.uid()
    )
  );

create policy "usuario registra los puntos de sus propios entrenamientos"
  on puntos_gps for insert
  with check (
    exists (
      select 1 from entrenamientos e
      where e.id = puntos_gps.entrenamiento_id
        and e.usuario_id = auth.uid()
    )
  );

-- -------------------------------------------------------------
-- 3. permisos_usuario
--
-- Un upsert por usuario y tipo, sin ignorar duplicados: hace
-- `do update`, así que necesita insert **y** update.
-- -------------------------------------------------------------
drop policy "usuario gestiona sus propios permisos" on permisos_usuario;

create policy "usuario ve sus propios permisos"
  on permisos_usuario for select
  using (auth.uid() = usuario_id);

create policy "usuario registra sus propios permisos"
  on permisos_usuario for insert
  with check (auth.uid() = usuario_id);

create policy "usuario actualiza sus propios permisos"
  on permisos_usuario for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 4. objetivos
--
-- **La excepción.** Aquí el borrado es parte del producto: al
-- editar sus metas, el usuario desmarca un tipo y esa fila se
-- quita (`objetivos_service.dart`). Conserva DELETE, y por eso
-- es la única tabla a la que no se le revoca el privilegio.
-- -------------------------------------------------------------
drop policy "usuario gestiona sus propios objetivos" on objetivos;

create policy "usuario ve sus propios objetivos"
  on objetivos for select
  using (auth.uid() = usuario_id);

create policy "usuario registra sus propios objetivos"
  on objetivos for insert
  with check (auth.uid() = usuario_id);

create policy "usuario actualiza sus propios objetivos"
  on objetivos for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

create policy "usuario quita sus propios objetivos"
  on objetivos for delete
  using (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 5. perfiles
--
-- Sigue pudiéndose escribir, igual que hasta ahora: lo único que
-- pierde es el borrado. Hoy la app solo lee de aquí (el rol, en
-- `rol_provider.dart`) y ni siquiera guarda los datos físicos de
-- 0004, pero se deja abierta la escritura sobre la propia fila
-- para no romper una pantalla de editar perfil que esté en curso
-- en otra rama.
--
-- OJO, y esto no lo arregla esta migración: `update` sobre la
-- propia fila incluye la columna `rol`, y `es_admin()` (0005)
-- autoriza mirando esa columna. Un usuario puede ponerse
-- 'admin' y ganar permisos de administrador de verdad, no solo
-- en la interfaz. Ya era así antes de esta migración, con la
-- policy `for all`; queda igual, no mejor. Cerrarlo es una línea
-- —`revoke update (rol) on perfiles from anon, authenticated`—
-- que no afecta a la app, porque la app no escribe el rol, pero
-- es una decisión aparte y está sin tomar.
-- -------------------------------------------------------------
drop policy "usuario ve y edita su propio perfil" on perfiles;

create policy "usuario ve su propio perfil"
  on perfiles for select
  using (auth.uid() = id);

create policy "usuario crea su propio perfil"
  on perfiles for insert
  with check (auth.uid() = id);

create policy "usuario edita su propio perfil"
  on perfiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- -------------------------------------------------------------
-- 6. El privilegio, no solo la policy
--
-- Supabase concede todos los privilegios a `anon` y
-- `authenticated` al crear una tabla en `public`, y deja que RLS
-- sea la única puerta. Sin policy de delete, un DELETE no borra
-- filas, pero **no falla**: devuelve "0 filas" en silencio. Sin el
-- privilegio, falla con 42501, que es lo que se quiere.
--
-- `objetivos` no está en esta lista: ahí el borrado es legítimo.
-- -------------------------------------------------------------
revoke delete on table entrenamientos from anon, authenticated;
revoke delete on table puntos_gps from anon, authenticated;
revoke delete on table permisos_usuario from anon, authenticated;
revoke delete on table perfiles from anon, authenticated;

-- =============================================================
-- COMPROBACIÓN (correr después, en el SQL Editor, como un script
-- aparte)
--
-- Va entera dentro de una transacción que termina en ROLLBACK: no
-- deja nada en la base, ni siquiera el entrenamiento de prueba.
--
-- Antes de pegarla, cambia <USUARIO> por un id de `auth.users` que
-- tenga perfil. El SQL Editor corre como `postgres`, que es el
-- dueño de las tablas y se salta RLS, así que la cabecera se hace
-- pasar por ese usuario (lo mismo que explica 0052).
--
-- El resultado es el aviso del final:
--   "VERIFICACIÓN OK"  → todo cumple.
--   "FALLÓ: …"         → eso no cumple, y lo dice.
-- =============================================================
/*
begin;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', '<USUARIO>', 'role', 'authenticated')::text,
  true
);
set local role authenticated;

do $$
declare
  v_tipo   uuid;
  v_ent    uuid;
  v_fallos text := '';
begin
  if auth.uid() is null then
    raise exception 'La cabecera no se aplicó: auth.uid() es nulo. '
      'La cabecera y el script van en la MISMA ejecución.';
  end if;

  select id into v_tipo from tipos_actividad limit 1;

  -- 1. Insertar un entrenamiento: tiene que poder.
  begin
    insert into entrenamientos (usuario_id, tipo_actividad_id, estado)
    values (auth.uid(), v_tipo, 'en_curso')
    returning id into v_ent;
  exception when others then
    v_fallos := v_fallos || 'no pudo insertar en entrenamientos (' ||
      sqlstate || '); ';
  end;

  -- 2. Actualizarlo: tiene que poder (es lo que hace finalizar y
  --    cancelar). Pasa a 'cancelado' a proposito: 'finalizado'
  --    dispararia el trigger de XP de 0009 y escribiria en
  --    experiencia_ganada, que no es lo que se comprueba aqui.
  if v_ent is not null then
    begin
      update entrenamientos set estado = 'cancelado' where id = v_ent;
    exception when others then
      v_fallos := v_fallos || 'no pudo actualizar entrenamientos (' ||
        sqlstate || '); ';
    end;

    -- 3. Insertar un punto de ese entrenamiento: tiene que poder.
    begin
      insert into puntos_gps
        (entrenamiento_id, latitud, longitud, orden_secuencia)
      values (v_ent, 6.2442, -75.5812, 0);
    exception when others then
      v_fallos := v_fallos || 'no pudo insertar en puntos_gps (' ||
        sqlstate || '); ';
    end;

    -- 4. Borrar el entrenamiento: NO tiene que poder.
    begin
      delete from entrenamientos where id = v_ent;
      v_fallos := v_fallos || 'PUDO BORRAR de entrenamientos; ';
    exception when insufficient_privilege then
      null;  -- 42501, que es lo esperado
    end;

    -- 5. Borrar sus puntos: NO tiene que poder.
    begin
      delete from puntos_gps where entrenamiento_id = v_ent;
      v_fallos := v_fallos || 'PUDO BORRAR de puntos_gps; ';
    exception when insufficient_privilege then
      null;
    end;
  end if;

  -- 6. permisos_usuario: insertar y actualizar, sí; borrar, no.
  begin
    insert into permisos_usuario (usuario_id, tipo_permiso, concedido)
    values (auth.uid(), 'ubicacion', true)
    on conflict (usuario_id, tipo_permiso)
      do update set concedido = excluded.concedido;
  exception when others then
    v_fallos := v_fallos || 'no pudo guardar permisos_usuario (' ||
      sqlstate || '); ';
  end;

  begin
    delete from permisos_usuario where usuario_id = auth.uid();
    v_fallos := v_fallos || 'PUDO BORRAR de permisos_usuario; ';
  exception when insufficient_privilege then
    null;
  end;

  -- 7. perfiles: leer y editar su fila, sí; borrarla, no.
  begin
    perform 1 from perfiles where id = auth.uid();
  exception when others then
    v_fallos := v_fallos || 'no pudo leer su perfil (' || sqlstate || '); ';
  end;

  -- Se reescribe el nombre con el que ya tiene, para no depender
  -- de ningún valor concreto. El rollback lo deshace igual.
  begin
    update perfiles set nombre = nombre where id = auth.uid();
  exception when others then
    v_fallos := v_fallos || 'no pudo editar su perfil (' ||
      sqlstate || '); ';
  end;

  begin
    delete from perfiles where id = auth.uid();
    v_fallos := v_fallos || 'PUDO BORRAR su perfil; ';
  exception when insufficient_privilege then
    null;
  end;

  -- 8. objetivos: la excepción. Insertar, actualizar y borrar, sí.
  begin
    insert into objetivos (usuario_id, tipo, valor_meta)
    values (auth.uid(), 'distancia', 10)
    on conflict (usuario_id, tipo)
      do update set valor_meta = excluded.valor_meta;
    delete from objetivos
     where usuario_id = auth.uid() and tipo = 'distancia';
  exception when others then
    v_fallos := v_fallos || 'no pudo gestionar objetivos (' ||
      sqlstate || '); ';
  end;

  if v_fallos = '' then
    raise notice 'VERIFICACIÓN OK';
  else
    raise notice 'FALLÓ: %', v_fallos;
  end if;
end
$$;

rollback;
*/

-- =============================================================
-- MARCHA ATRÁS (solo si hay que deshacer esta migración)
--
-- Devuelve las cinco policies `for all` y el privilegio DELETE
-- exactamente como estaban antes: la definición de 0001 y 0002,
-- copiada tal cual.
--
-- Deshacer esto vuelve a permitir que el dueño de un entrenamiento
-- lo borre, y con él su traza y su XP. No se hace "por si acaso":
-- se hace solo si algo de la app dejó de funcionar y hace falta
-- tiempo para arreglarlo bien.
-- =============================================================
/*
drop policy "usuario ve sus propios entrenamientos" on entrenamientos;
drop policy "usuario registra sus propios entrenamientos" on entrenamientos;
drop policy "usuario actualiza sus propios entrenamientos" on entrenamientos;

drop policy "usuario ve los puntos de sus propios entrenamientos" on puntos_gps;
drop policy "usuario registra los puntos de sus propios entrenamientos"
  on puntos_gps;

drop policy "usuario ve sus propios permisos" on permisos_usuario;
drop policy "usuario registra sus propios permisos" on permisos_usuario;
drop policy "usuario actualiza sus propios permisos" on permisos_usuario;

drop policy "usuario ve sus propios objetivos" on objetivos;
drop policy "usuario registra sus propios objetivos" on objetivos;
drop policy "usuario actualiza sus propios objetivos" on objetivos;
drop policy "usuario quita sus propios objetivos" on objetivos;

drop policy "usuario ve su propio perfil" on perfiles;
drop policy "usuario crea su propio perfil" on perfiles;
drop policy "usuario edita su propio perfil" on perfiles;

-- Tal cual en 0001_init_sprint1.sql
create policy "usuario gestiona sus propios permisos"
  on permisos_usuario
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

create policy "usuario gestiona sus propios objetivos"
  on objetivos
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

create policy "usuario gestiona sus propios entrenamientos"
  on entrenamientos
  for all
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

create policy "usuario gestiona los puntos de sus propios entrenamientos"
  on puntos_gps
  for all
  using (
    exists (
      select 1 from entrenamientos e
      where e.id = puntos_gps.entrenamiento_id
        and e.usuario_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from entrenamientos e
      where e.id = puntos_gps.entrenamiento_id
        and e.usuario_id = auth.uid()
    )
  );

-- Tal cual en 0002_perfiles.sql
create policy "usuario ve y edita su propio perfil"
  on perfiles
  for all
  using (auth.uid() = id)
  with check (auth.uid() = id);

grant delete on table entrenamientos to anon, authenticated;
grant delete on table puntos_gps to anon, authenticated;
grant delete on table permisos_usuario to anon, authenticated;
grant delete on table perfiles to anon, authenticated;
*/
