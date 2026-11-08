-- =============================================================
-- TRAZA — RNF-14: que nadie se dé el rol de administrador
--
-- `es_admin()` (0005) decide quién administra mirando
-- `perfiles.rol`. La policy "usuario edita su propio perfil"
-- (0056) deja a cada usuario modificar su fila sin límite de
-- columnas, y eso incluye `rol`. La app nunca lo escribe, pero
-- cualquiera con la publishable key (va dentro del APK) y su
-- propia sesión puede llamar a la API REST y ponerse
-- `rol = 'admin'`. Desde ahí, todas las funciones y policies que
-- preguntan `es_admin()` lo dejan pasar: retos, niveles,
-- recompensas, moderación del foro, revisión de rutas, rutas
-- oficiales.
--
-- El arreglo que se anotó en 0056 y en docs/deudas.md
-- (`revoke update (rol) on perfiles ...`) NO funciona: en Postgres,
-- quitar una columna no tiene efecto mientras el rol tenga
-- `update` sobre la tabla entera, y Supabase se lo da a
-- `authenticated`.
--
-- Decisión: un trigger, como `horas_del_servidor` (0061). Si la
-- escritura llega por la API (`authenticated` o `anon`), `rol` no
-- cambia; al crear un perfil, siempre nace `usuario`. Lo demás del
-- perfil se sigue editando igual. Nombrar a un administrador se
-- hace como hasta ahora, desde el SQL Editor (rol postgres), donde
-- el trigger no interviene. El alta de usuarios tampoco cambia:
-- `handle_new_user` (0002) es `security definer` y corre como
-- postgres.
--
-- No depende de 0059–0061: el número sigue al último que ya usan
-- las ramas de rutas oficiales. Se puede aplicar antes que ellas.
-- =============================================================

create or replace function public.proteger_rol()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.rol := 'usuario';
  else
    new.rol := old.rol;
  end if;
  return new;
end;
$$;

create trigger perfiles_proteger_rol
  before insert or update on perfiles
  for each row execute function public.proteger_rol();

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un corredor y un administrador de prueba. Al final lanza un
-- error A PROPÓSITO para que todo se deshaga. El resultado es el
-- mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_corredor  uuid := gen_random_uuid();
  v_admin     uuid := gen_random_uuid();
  v_nuevo     uuid := gen_random_uuid();
  v_n         integer;
begin
  -- `handle_new_user` (0002) crea el perfil de cada uno.
  insert into auth.users (id, email) values
    (v_corredor, 'prueba-rol-' || v_corredor || '@traza.test'),
    (v_admin,    'prueba-rol-' || v_admin    || '@traza.test'),
    (v_nuevo,    'prueba-rol-' || v_nuevo    || '@traza.test');

  -- Nombrar administrador desde el SQL Editor sigue funcionando.
  update perfiles set rol = 'admin' where id = v_admin;
  select count(*) into v_n from perfiles where id = v_admin and rol = 'admin';
  if v_n <> 1 then raise exception 'FALLÓ: el SQL Editor ya no puede nombrar administradores'; end if;

  -- El corredor intenta darse el rol por la API.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update perfiles set rol = 'admin' where id = v_corredor;
  if public.es_admin() then
    raise exception 'FALLÓ: un corredor se dio el rol de administrador';
  end if;

  -- Su perfil se sigue editando: el nombre cambia, el rol no.
  update perfiles set nombre = 'Nombre editado', rol = 'admin' where id = v_corredor;
  select count(*) into v_n from perfiles
    where id = v_corredor and nombre = 'Nombre editado' and rol = 'usuario';
  if v_n <> 1 then raise exception 'FALLÓ: editar el perfil cambió el rol o no guardó el nombre'; end if;

  -- Tampoco con un upsert, que es lo que manda PostgREST con
  -- `Prefer: resolution=merge-duplicates`.
  insert into perfiles (id, nombre, rol) values (v_corredor, 'Upsert', 'admin')
    on conflict (id) do update set nombre = excluded.nombre, rol = excluded.rol;
  if public.es_admin() then
    raise exception 'FALLÓ: un corredor se dio el rol con un upsert';
  end if;

  -- El administrador edita su perfil desde la app y sigue siéndolo.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update perfiles set nombre = 'Admin editado' where id = v_admin;
  if not public.es_admin() then
    raise exception 'FALLÓ: el administrador perdió el rol al editar su perfil';
  end if;
  -- Y tampoco se lo puede quitar por la API (se cambia desde el SQL Editor).
  update perfiles set rol = 'usuario' where id = v_admin;
  if not public.es_admin() then
    raise exception 'FALLÓ: el rol del administrador cambió por la API';
  end if;

  -- Un perfil creado por la API nace usuario, aunque pida admin.
  reset role;
  delete from perfiles where id = v_nuevo;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_nuevo, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into perfiles (id, nombre, rol) values (v_nuevo, 'Nuevo', 'admin');
  if public.es_admin() then
    raise exception 'FALLÓ: un perfil creado por la API nació administrador';
  end if;

  raise exception 'VERIFICACIÓN OK: perfiles.rol solo cambia desde el SQL Editor (todo se deshace)';
end;
$$;
*/

-- =============================================================
-- REVISIÓN (correr una vez, aparte, después de aplicar)
--
-- El hueco existía desde 0005: si alguien ya se dio el rol, esta
-- migración no se lo quita. Comparar con la lista de quienes deben
-- ser administradores y, a cualquier otro, bajarle el rol desde el
-- SQL Editor con `update perfiles set rol = 'usuario' where id = ...`.
-- =============================================================
/*
select p.id, u.email, p.nombre
from perfiles p
join auth.users u on u.id = p.id
where p.rol = 'admin';
*/
