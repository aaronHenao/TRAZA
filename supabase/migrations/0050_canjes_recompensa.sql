-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-380: modificar los puntos de una
-- recompensa
--
-- El administrador cambia los puntos que pide una recompensa y el
-- catálogo de los corredores muestra el valor nuevo (criterio 1).
-- Lo inválido lo rechazan los `check` de 0037 y la fila conserva
-- su valor (criterio 2).
--
-- El criterio 3 pide que los canjes ya hechos no cambien. Por eso
-- nace aquí `canjes_recompensa`: cada canje guarda los puntos que
-- costó en ese momento, en su propia columna, y no los lee de
-- `recompensas`. Cambiar el precio después no lo toca.
--
-- Decisiones:
--
--   · Canjear (validar el saldo y descontar) es de otra HU. Esta
--     solo crea la tabla con lo que el criterio 3 necesita. Nadie
--     inserta desde la app: no hay policy de insert. Cuando exista
--     el canje, entrará por una función `security definer`.
--
--   · Los puntos del canje los copia la base, no el cliente: un
--     trigger los toma de `recompensas` al insertar. Así el valor
--     guardado es siempre el precio vigente en ese momento, venga
--     de donde venga el insert. Otro trigger los deja fijos en
--     cualquier update: el criterio 3 no depende de que nadie
--     agregue después una policy de update.
--
--   · `on delete restrict` hacia `recompensas`: una recompensa con
--     canjes no se borra. Retirarla (SCRUM-385) no borra la fila.
--
--   · El administrador puede cambiar cualquier columna de la
--     recompensa, igual que en los demás catálogos que gestiona;
--     los `check` de 0037 siguen valiendo en el update.
--
-- Corre esto DESPUÉS de 0037_recompensas.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. El administrador cambia los puntos (criterio 1)
-- -------------------------------------------------------------
create policy "solo el administrador edita recompensas"
  on recompensas for update
  to authenticated
  using (public.es_admin())
  with check (public.es_admin());

-- -------------------------------------------------------------
-- 2. Los canjes guardan su precio (criterio 3)
-- -------------------------------------------------------------
create table canjes_recompensa (
  id                uuid primary key default gen_random_uuid(),
  recompensa_id     uuid not null references recompensas(id) on delete restrict,
  usuario_id        uuid not null references auth.users(id) on delete cascade,
  -- Lo que costó en el momento del canje. No se recalcula nunca.
  puntos_canjeados  integer not null,
  fecha             timestamptz not null default now(),

  constraint canjes_recompensa_puntos_positivos
    check (puntos_canjeados > 0)
);

-- "Mis canjes" y la policy de select.
create index canjes_recompensa_usuario_idx
  on canjes_recompensa (usuario_id, fecha desc);

-- Saber si una recompensa tiene canjes (SCRUM-385).
create index canjes_recompensa_recompensa_idx
  on canjes_recompensa (recompensa_id);

-- El precio y la fecha los pone la base.
--
-- Sin `security definer` a propósito: lee `recompensas` con el RLS
-- de quien inserta, así una recompensa que el corredor no puede
-- ver (no disponible) no se puede canjear aunque alguien abra una
-- policy de insert. La función de canje, cuando exista, correrá
-- como su dueño y sí la verá.
create function public.preparar_canje_recompensa()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  select r.puntos_requeridos
    into new.puntos_canjeados
  from recompensas r
  where r.id = new.recompensa_id;

  -- Sin esto fallaría el `not null` del precio, que no explica nada.
  if not found then
    raise exception 'La recompensa % no existe', new.recompensa_id
      using errcode = 'foreign_key_violation';
  end if;

  new.fecha := now();
  return new;
end;
$$;

create trigger canjes_recompensa_preparar
  before insert on canjes_recompensa
  for each row execute function public.preparar_canje_recompensa();

-- Un canje no cambia de recompensa, de dueño, de precio ni de
-- fecha (criterio 3). Si algún día se agrega una columna que sí se
-- actualiza (por ejemplo, si ya se entregó), esto sigue valiendo.
create function public.proteger_canje_recompensa()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.id := old.id;
  new.recompensa_id := old.recompensa_id;
  new.usuario_id := old.usuario_id;
  new.puntos_canjeados := old.puntos_canjeados;
  new.fecha := old.fecha;
  return new;
end;
$$;

create trigger canjes_recompensa_proteger
  before update on canjes_recompensa
  for each row execute function public.proteger_canje_recompensa();

-- Solo las usan los triggers. Nadie las llama directo.
revoke execute on function public.preparar_canje_recompensa()
  from public, anon, authenticated;
revoke execute on function public.proteger_canje_recompensa()
  from public, anon, authenticated;

-- -------------------------------------------------------------
-- 3. RLS
--
-- Cada corredor ve sus canjes; el administrador, todos. Nadie
-- escribe desde la app todavía: sin policies de insert, update
-- ni delete. Un canje no se edita: su precio queda fijo.
-- -------------------------------------------------------------
alter table canjes_recompensa enable row level security;

create policy "el usuario ve sus propios canjes"
  on canjes_recompensa for select
  to authenticated
  using (auth.uid() = usuario_id);

create policy "el administrador ve todos los canjes"
  on canjes_recompensa for select
  to authenticated
  using (public.es_admin());

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un corredor y un administrador de prueba y revisa los
-- criterios 1 a 3 y el RLS. Al final lanza un error A PROPÓSITO
-- para que todo se deshaga: no deja nada en la base. El resultado
-- es el mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_corredor    uuid := gen_random_uuid();
  v_admin       uuid := gen_random_uuid();
  v_recompensa  uuid;
  v_canje       uuid;
  v_ajeno       uuid;
  v_n           integer;
  v_puntos      integer;
begin
  insert into auth.users (id, email) values
    (v_corredor, 'prueba-canjes-' || v_corredor || '@traza.test'),
    (v_admin,    'prueba-canjes-' || v_admin    || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;

  insert into recompensas (nombre, descripcion, puntos_requeridos)
    values ('Prueba canjes', 'Vale 150 al canjear', 150)
    returning id into v_recompensa;

  -- Un canje hecho antes del cambio. Se inserta como dueño de la
  -- base (la app todavía no canjea), mandando un precio falso a
  -- propósito: el trigger lo cambia por el vigente.
  insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
    values (v_recompensa, v_corredor, 1)
    returning id into v_canje;
  select puntos_canjeados into v_puntos from canjes_recompensa where id = v_canje;
  if v_puntos is distinct from 150 then
    raise exception 'FALLÓ criterio 3: el canje guardó % puntos, esperaba el precio vigente (150)', v_puntos;
  end if;

  -- Un canje de otro usuario, que el corredor no debe ver.
  insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
    values (v_recompensa, v_admin, 1)
    returning id into v_ajeno;

  -- Una recompensa que no existe se explica como tal.
  begin
    insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
      values (gen_random_uuid(), v_corredor, 1);
    raise exception 'FALLÓ: se canjeó una recompensa que no existe';
  exception when foreign_key_violation then null;
  end;

  -- Criterio 1: el administrador cambia los puntos.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  update recompensas set puntos_requeridos = 200 where id = v_recompensa;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'FALLÓ criterio 1: el administrador cambió % recompensas, esperaba 1', v_n; end if;

  -- Criterio 2: lo inválido no entra y deja el valor como estaba.
  begin
    update recompensas set puntos_requeridos = 0 where id = v_recompensa;
    raise exception 'FALLÓ criterio 2: se guardaron 0 puntos';
  exception when check_violation then null;
  end;
  begin
    update recompensas set puntos_requeridos = -5 where id = v_recompensa;
    raise exception 'FALLÓ criterio 2: se guardaron puntos negativos';
  exception when check_violation then null;
  end;
  begin
    update recompensas set puntos_requeridos = 1000001 where id = v_recompensa;
    raise exception 'FALLÓ criterio 2: se guardaron más de un millón de puntos';
  exception when check_violation then null;
  end;

  -- Criterio 1: el corredor ve el valor nuevo en su catálogo.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  select puntos_requeridos into v_puntos from recompensas where id = v_recompensa;
  if v_puntos is distinct from 200 then
    raise exception 'FALLÓ criterio 1/2: el corredor ve % puntos, esperaba 200', v_puntos;
  end if;

  -- Criterio 3: su canje conserva el valor anterior.
  select puntos_canjeados into v_puntos from canjes_recompensa where id = v_canje;
  if v_puntos is distinct from 150 then
    raise exception 'FALLÓ criterio 3: el canje anterior quedó en % puntos, esperaba 150', v_puntos;
  end if;

  -- El corredor no cambia los puntos ni toca su canje. En update y
  -- delete RLS no da error: deja 0 filas.
  begin
    update recompensas set puntos_requeridos = 1 where id = v_recompensa;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor cambió los puntos de % recompensas', v_n; end if;
  begin
    update canjes_recompensa set puntos_canjeados = 1 where id = v_canje;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor cambió el precio de % canjes', v_n; end if;
  begin
    delete from canjes_recompensa where id = v_canje;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor borró % canjes', v_n; end if;
  begin
    insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
      values (v_recompensa, v_corredor, 1);
    raise exception 'FALLÓ RLS: el corredor canjeó desde la API';
  exception when insufficient_privilege then null;
  end;

  -- Ve su canje, y no el de otro usuario.
  select count(*) into v_n from canjes_recompensa where id = v_canje;
  if v_n <> 1 then raise exception 'FALLÓ RLS: el corredor no ve su propio canje'; end if;
  select count(*) into v_n from canjes_recompensa where id = v_ajeno;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor ve el canje de otro usuario'; end if;

  -- Criterio 3: el administrador tampoco reescribe un canje.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  begin
    update canjes_recompensa set puntos_canjeados = 200 where id = v_canje;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ criterio 3: el administrador recalculó % canjes', v_n; end if;
  select count(*) into v_n from canjes_recompensa where id = v_canje;
  if v_n <> 1 then raise exception 'FALLÓ RLS: el administrador no ve el canje'; end if;

  -- Sin sesión (anon) no se ve ningún canje.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
  begin
    select count(*) into v_n from canjes_recompensa;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: sin sesión se ven % canjes', v_n; end if;

  reset role;

  -- Criterio 3: ni el dueño de la base, que salta el RLS, le cambia
  -- el precio a un canje.
  update canjes_recompensa set puntos_canjeados = 999 where id = v_canje;
  select puntos_canjeados into v_puntos from canjes_recompensa where id = v_canje;
  if v_puntos is distinct from 150 then
    raise exception 'FALLÓ criterio 3: un update dejó el canje en % puntos, esperaba 150', v_puntos;
  end if;

  -- Criterio 3: un canje posterior ya toma el valor nuevo.
  insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
    values (v_recompensa, v_corredor, 1)
    returning id into v_canje;
  select puntos_canjeados into v_puntos from canjes_recompensa where id = v_canje;
  if v_puntos is distinct from 200 then
    raise exception 'FALLÓ criterio 3: el canje posterior guardó % puntos, esperaba 200', v_puntos;
  end if;

  -- Con canjes, la recompensa no se puede borrar.
  begin
    delete from recompensas where id = v_recompensa;
    raise exception 'FALLÓ: se borró una recompensa con canjes';
  exception when foreign_key_violation then null;
  end;

  raise exception 'VERIFICACIÓN OK: criterios 1 a 3 y RLS de canjes_recompensa. (Este error deshace los datos de prueba.)';
end;
$$;
*/
