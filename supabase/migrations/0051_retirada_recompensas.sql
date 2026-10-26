-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-385: eliminar recompensas
--
-- El administrador elimina una recompensa que ya no existe para
-- que nadie intente canjearla (criterio 2). Los canjes que se
-- hicieron antes siguen en el historial de quien canjeó
-- (criterio 3).
--
-- Eliminar es retirar, no borrar: la fila se queda con la fecha
-- en `retirada_en`, igual que los retos (0018). `canjes_recompensa`
-- apunta a ella con `on delete restrict` (0038), y borrarla dejaría
-- esos canjes sin saber qué se canjeó.
--
-- Decisiones:
--
--   · Se puede retirar cualquier recompensa, disponible o no: lo
--     que dice la HU es que el beneficio ya no existe.
--
--   · Es definitivo (criterio 1: "eliminarla definitivamente").
--     Un trigger no deja quitar la fecha una vez puesta, y la fecha
--     la pone la base, no el cliente.
--
--   · El corredor deja de ver la retirada en su catálogo, salvo
--     que la haya canjeado: para su historial sigue pudiendo leerla
--     (como hace 0018 con los retos que ya había activado), igual
--     que una que el administrador dejó no disponible. Qué se
--     muestra en el catálogo lo filtra la consulta.
--
--   · Que pueda leerla no quiere decir que pueda canjearla: el
--     trigger de 0038 que pone el precio del canje ahora exige que
--     esté disponible y no retirada.
--
--   · Si alguna vez hay que deshacer un retiro (por ejemplo, uno
--     hecho por error), solo el dueño de la base puede, en el SQL
--     Editor:
--       alter table recompensas disable trigger recompensas_sellar_retirada;
--       update recompensas set retirada_en = null where id = '...';
--       alter table recompensas enable trigger recompensas_sellar_retirada;
--
-- Corre esto DESPUÉS de 0038_canjes_recompensa.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La marca de retiro
-- -------------------------------------------------------------
alter table recompensas
  add column retirada_en timestamptz;

-- La fecha la pone la base; una vez puesta no se quita. Al crear
-- no se puede nacer retirada.
create function public.sellar_retirada_recompensa()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.retirada_en := null;
  elsif old.retirada_en is not null then
    new.retirada_en := old.retirada_en;
  elsif new.retirada_en is not null then
    new.retirada_en := now();
  end if;
  return new;
end;
$$;

create trigger recompensas_sellar_retirada
  before insert or update on recompensas
  for each row execute function public.sellar_retirada_recompensa();

revoke execute on function public.sellar_retirada_recompensa()
  from public, anon, authenticated;

-- -------------------------------------------------------------
-- 2. Quién ve una recompensa retirada (criterios 2 y 3)
--
-- Se reemplaza la policy de select de 0037. Las policies de select
-- se suman (OR): la segunda solo alcanza a las recompensas que ese
-- mismo corredor canjeó.
-- -------------------------------------------------------------
drop policy "recompensas disponibles para los corredores, todas para el admin"
  on recompensas;

create policy "recompensas vigentes para los corredores, todas para el admin"
  on recompensas for select
  to authenticated
  using ((disponible and retirada_en is null) or public.es_admin());

create policy "el corredor ve las recompensas que ya canjeó"
  on recompensas for select
  to authenticated
  using (
    exists (
      select 1
      from canjes_recompensa c
      where c.recompensa_id = recompensas.id
        and c.usuario_id = auth.uid()
    )
  );

-- -------------------------------------------------------------
-- 3. Lo retirado no se canjea
--
-- Reemplaza la función de 0038: es la misma pregunta (cuánto
-- cuesta lo que se canjea), ahora solo entre lo disponible y no
-- retirado. Antes bastaba el RLS para descartar lo no disponible,
-- pero la policy de "ya la canjeé" se la deja ver a quien la canjeó.
-- -------------------------------------------------------------
create or replace function public.preparar_canje_recompensa()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  select r.puntos_requeridos
    into new.puntos_canjeados
  from recompensas r
  where r.id = new.recompensa_id
    and r.disponible
    and r.retirada_en is null;

  if not found then
    raise exception 'La recompensa % no existe, no está disponible o fue retirada',
      new.recompensa_id
      using errcode = 'foreign_key_violation';
  end if;

  new.fecha := now();
  return new;
end;
$$;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un corredor que canjeó, otro que no y un administrador de
-- prueba, y revisa los criterios 2 y 3 y el RLS. (El criterio 1,
-- confirmar antes de eliminar, es de la app.) Al final lanza un
-- error A PROPÓSITO para que todo se deshaga: no deja nada en la
-- base. El resultado es el mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_canjeo      uuid := gen_random_uuid();
  v_otro        uuid := gen_random_uuid();
  v_admin       uuid := gen_random_uuid();
  v_recompensa  uuid;
  v_oculta      uuid;
  v_vigente     uuid;
  v_canje       uuid;
  v_fecha       timestamptz;
  v_n           integer;
  v_puntos      integer;
  v_nombre      text;
begin
  insert into auth.users (id, email) values
    (v_canjeo, 'prueba-retirada-' || v_canjeo || '@traza.test'),
    (v_otro,   'prueba-retirada-' || v_otro   || '@traza.test'),
    (v_admin,  'prueba-retirada-' || v_admin  || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;

  -- Al crearla no puede nacer retirada.
  insert into recompensas (nombre, descripcion, puntos_requeridos, retirada_en)
    values ('Prueba retirada', 'Se elimina en esta prueba', 150, now())
    returning id into v_recompensa;
  select retirada_en into v_fecha from recompensas where id = v_recompensa;
  if v_fecha is not null then raise exception 'FALLÓ: una recompensa nació retirada'; end if;

  insert into recompensas (nombre, descripcion, puntos_requeridos, disponible)
    values ('Prueba oculta', 'No disponible', 300, false)
    returning id into v_oculta;
  insert into recompensas (nombre, descripcion, puntos_requeridos)
    values ('Prueba vigente', 'Nadie la retira', 50)
    returning id into v_vigente;

  -- Un canje anterior a la eliminación (la app todavía no canjea).
  insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
    values (v_recompensa, v_canjeo, 1)
    returning id into v_canje;

  -- Criterio 2: el administrador la retira. Manda una fecha vieja:
  -- la base pone la de ahora.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  update recompensas set retirada_en = '2000-01-01' where id = v_recompensa;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'FALLÓ criterio 2: el administrador retiró % recompensas, esperaba 1', v_n; end if;
  select retirada_en into v_fecha from recompensas where id = v_recompensa;
  if v_fecha is distinct from now() then
    raise exception 'FALLÓ: la fecha de retiro la eligió el cliente (%)', v_fecha;
  end if;

  -- Una que no estaba disponible también se retira.
  update recompensas set retirada_en = now() where id = v_oculta;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'FALLÓ criterio 2: no se retiró una recompensa no disponible'; end if;

  -- Es definitivo: quitar la fecha no la devuelve, y volver a
  -- retirarla no se la cambia.
  update recompensas set retirada_en = null where id = v_recompensa;
  select retirada_en into v_fecha from recompensas where id = v_recompensa;
  if v_fecha is null then raise exception 'FALLÓ criterio 1: una recompensa retirada volvió al catálogo'; end if;
  update recompensas set retirada_en = now() + interval '1 day' where id = v_recompensa;
  select retirada_en into v_fecha from recompensas where id = v_recompensa;
  if v_fecha is distinct from now() then
    raise exception 'FALLÓ criterio 1: volver a retirarla le cambió la fecha (%)', v_fecha;
  end if;

  -- Retirar no es borrar: nadie borra desde la app.
  begin
    delete from recompensas where id = v_recompensa;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ criterio 3: el administrador borró % recompensas', v_n; end if;

  -- Criterio 2: quien no la canjeó ya no la ve.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_otro, 'role', 'authenticated')::text, true);
  select count(*) into v_n from recompensas where id in (v_recompensa, v_oculta);
  if v_n <> 0 then raise exception 'FALLÓ criterio 2: un corredor ve % recompensas retiradas', v_n; end if;

  -- Un corredor no retira nada.
  begin
    update recompensas set retirada_en = now() where id = v_vigente;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: un corredor retiró % recompensas', v_n; end if;

  -- Quien canjeó una sigue leyendo esa (para su historial; del
  -- catálogo la saca la consulta), pero no las retiradas que no
  -- canjeó.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_canjeo, 'role', 'authenticated')::text, true);
  select count(*) into v_n from recompensas where id = v_recompensa;
  if v_n <> 1 then raise exception 'FALLÓ criterio 3: quien la canjeó ya no puede leerla'; end if;
  select count(*) into v_n from recompensas where id = v_oculta;
  if v_n <> 0 then raise exception 'FALLÓ RLS: quien canjeó otra ve una retirada que no canjeó'; end if;

  -- Criterio 3: pero conserva su canje, con lo que costó y a qué
  -- recompensa apunta.
  select c.puntos_canjeados, r.nombre into v_puntos, v_nombre
  from canjes_recompensa c
  join recompensas r on r.id = c.recompensa_id
  where c.id = v_canje;
  if v_puntos is distinct from 150 or v_nombre is distinct from 'Prueba retirada' then
    raise exception 'FALLÓ criterio 3: el historial dice % puntos de "%", esperaba 150 de "Prueba retirada"', v_puntos, v_nombre;
  end if;

  -- Sin sesión (anon) no se ve nada.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
  begin
    select count(*) into v_n from recompensas where id = v_recompensa;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: sin sesión se ve una recompensa retirada'; end if;

  reset role;

  -- Lo retirado ya no se canjea.
  begin
    insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
      values (v_recompensa, v_canjeo, 1);
    raise exception 'FALLÓ criterio 2: se canjeó una recompensa retirada';
  exception when foreign_key_violation then null;
  end;

  -- Ni lo que no está disponible: lo exige el trigger, no solo el
  -- RLS (quien ya la canjeó la puede leer).
  update recompensas set disponible = false where id = v_vigente;
  begin
    insert into canjes_recompensa (recompensa_id, usuario_id, puntos_canjeados)
      values (v_vigente, v_canjeo, 1);
    raise exception 'FALLÓ: se canjeó una recompensa no disponible';
  exception when foreign_key_violation then null;
  end;

  -- Y con canjes, ni el dueño de la base la borra.
  begin
    delete from recompensas where id = v_recompensa;
    raise exception 'FALLÓ criterio 3: se borró una recompensa con canjes';
  exception when foreign_key_violation then null;
  end;

  raise exception 'VERIFICACIÓN OK: criterios 2 y 3, retiro definitivo y RLS de recompensas retiradas. (Este error deshace los datos de prueba.)';
end;
$$;
*/
