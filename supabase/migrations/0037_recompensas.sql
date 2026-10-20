-- =============================================================
-- TRAZA — Sprint 4 · SCRUM-374: crear recompensas
--
-- El administrador crea recompensas con nombre, descripción,
-- puntos requeridos y disponibilidad (criterio 1). Los corredores
-- ven en su catálogo las que están disponibles, con los puntos
-- que cuestan (criterio 3).
--
-- Decisiones:
--
--   · Las reglas del formulario (criterio 2) están también aquí,
--     como `check`: con la publishable key cualquiera puede llamar
--     a la API sin pasar por la app. Son las mismas de
--     `BorradorRecompensa` (`lib/models/recompensa.dart`): si
--     cambia una, cambia en los dos lados.
--
--   · La disponibilidad es un sí o un no, no un inventario: la HU
--     habla de "marcarla como disponible".
--
--   · Solo el administrador escribe (`es_admin()`, 0005). Cambiar
--     los puntos es de SCRUM-380 y retirar una recompensa es de
--     SCRUM-385: cada una trae su policy en su migración. Sin
--     policy de delete, a propósito: retirar no borra la fila,
--     para que los canjes sigan teniendo a qué apuntar.
--
-- Corre esto DESPUÉS de 0036_foro_reportes.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La tabla
-- -------------------------------------------------------------
create table recompensas (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null,
  descripcion        text not null,
  puntos_requeridos  integer not null,
  disponible         boolean not null default true,
  fecha_creacion     timestamptz not null default now(),

  -- El largo se mide sobre lo que se guarda, no sobre el texto
  -- recortado: si no, un nombre con millones de espacios al final
  -- pasaría. La app ya manda el texto recortado. `\S` exige algo
  -- que no sea blanco (espacio, salto de línea, tabulador...): una
  -- cadena de blancos no es un nombre.
  constraint recompensas_nombre_valido
    check (char_length(nombre) between 1 and 60 and nombre ~ '\S'),
  constraint recompensas_descripcion_valida
    check (char_length(descripcion) between 1 and 280 and descripcion ~ '\S'),
  -- El tope es `maxPuntosRecompensa`: sin él, un número enorme
  -- fallaría por desbordar la columna en vez de por esta regla.
  constraint recompensas_puntos_validos
    check (puntos_requeridos between 1 and 1000000)
);

-- -------------------------------------------------------------
-- 2. RLS
-- -------------------------------------------------------------
alter table recompensas enable row level security;

-- Lectura: el corredor ve lo disponible; el administrador, todo,
-- que necesita para su gestión. Qué se muestra en cada pantalla
-- (orden, filtros) lo decide la consulta.
create policy "recompensas disponibles para los corredores, todas para el admin"
  on recompensas for select
  to authenticated
  using (disponible or public.es_admin());

-- Escritura: solo el administrador.
create policy "solo el administrador crea recompensas"
  on recompensas for insert
  to authenticated
  with check (public.es_admin());

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
  v_corredor     uuid := gen_random_uuid();
  v_admin        uuid := gen_random_uuid();
  v_disponible   uuid;
  v_oculta       uuid;
  v_n            integer;
  v_puntos       integer;
begin
  insert into auth.users (id, email) values
    (v_corredor, 'prueba-recompensas-' || v_corredor || '@traza.test'),
    (v_admin,    'prueba-recompensas-' || v_admin    || '@traza.test');
  update perfiles set rol = 'admin' where id = v_admin;

  -- Criterio 1: el administrador crea una disponible y otra no.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into recompensas (nombre, descripcion, puntos_requeridos, disponible)
    values ('Prueba disponible', 'Se ve en el catálogo', 150, true)
    returning id into v_disponible;
  insert into recompensas (nombre, descripcion, puntos_requeridos, disponible)
    values ('Prueba oculta', 'Todavía no se ofrece', 300, false)
    returning id into v_oculta;

  select count(*) into v_n from recompensas where id in (v_disponible, v_oculta);
  if v_n <> 2 then raise exception 'FALLÓ criterio 1: el administrador ve % de sus 2 recompensas', v_n; end if;
  select count(*) into v_n from recompensas
    where id = v_oculta and nombre = 'Prueba oculta' and puntos_requeridos = 300 and not disponible;
  if v_n <> 1 then raise exception 'FALLÓ criterio 1: la recompensa no se guardó como se escribió'; end if;

  -- Los bordes que sí valen: 1 punto, un millón, 60 y 280
  -- caracteres.
  insert into recompensas (nombre, descripcion, puntos_requeridos, disponible)
    values (repeat('a', 60), repeat('b', 280), 1, false),
           ('Tope', 'Un millón de puntos', 1000000, false);

  -- Criterio 2: vacíos o puntos <= 0 no se guardan.
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('   ', 'Sin nombre', 10);
    raise exception 'FALLÓ criterio 2: se guardó una recompensa sin nombre';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values (E'\n\t', 'Nombre de blancos que no son espacios', 10);
    raise exception 'FALLÓ criterio 2: se guardó un nombre de saltos de línea y tabuladores';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Vale' || repeat(' ', 100), 'Relleno de espacios', 10);
    raise exception 'FALLÓ criterio 2: se guardó un nombre de más de 60 caracteres con espacios';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values (repeat('a', 61), 'Nombre largo', 10);
    raise exception 'FALLÓ criterio 2: se guardó un nombre de 61 caracteres';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Descripción larga', repeat('a', 281), 10);
    raise exception 'FALLÓ criterio 2: se guardó una descripción de 281 caracteres';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Sin descripción', '', 10);
    raise exception 'FALLÓ criterio 2: se guardó una recompensa sin descripción';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Gratis', 'Cero puntos', 0);
    raise exception 'FALLÓ criterio 2: se guardó una recompensa de 0 puntos';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Negativa', 'Puntos negativos', -5);
    raise exception 'FALLÓ criterio 2: se guardó una recompensa con puntos negativos';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Carísima', 'Pasa del tope', 1000001);
    raise exception 'FALLÓ criterio 2: se guardó una recompensa de más de un millón de puntos';
  exception when check_violation then null;
  end;
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Sin puntos', 'Puntos nulos', null);
    raise exception 'FALLÓ criterio 2: se guardó una recompensa sin puntos';
  exception when not_null_violation then null;
  end;

  -- Criterio 3: el corredor ve la disponible, con sus puntos, y
  -- no la oculta.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_corredor, 'role', 'authenticated')::text, true);

  select puntos_requeridos into v_puntos from recompensas where id = v_disponible;
  if v_puntos is distinct from 150 then
    raise exception 'FALLÓ criterio 3: el corredor ve la disponible con % puntos, esperaba 150', v_puntos;
  end if;
  select count(*) into v_n from recompensas where id = v_oculta;
  if v_n <> 0 then raise exception 'FALLÓ criterio 3: el corredor ve una recompensa no disponible'; end if;

  -- El corredor no crea, no edita ni borra. En update y delete RLS
  -- no da error: deja 0 filas.
  begin
    insert into recompensas (nombre, descripcion, puntos_requeridos)
      values ('Trampa', 'No debería existir', 1);
    raise exception 'FALLÓ RLS: el corredor creó una recompensa';
  exception when insufficient_privilege then null;
  end;
  begin
    update recompensas set puntos_requeridos = 1 where id = v_disponible;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor cambió los puntos de % recompensas', v_n; end if;
  begin
    delete from recompensas where id = v_disponible;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: el corredor borró % recompensas', v_n; end if;

  -- Sin sesión (anon) no se ve nada.
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
  begin
    select count(*) into v_n from recompensas;
  exception when insufficient_privilege then v_n := 0;
  end;
  if v_n <> 0 then raise exception 'FALLÓ RLS: sin sesión se ven % recompensas', v_n; end if;

  reset role;

  raise exception 'VERIFICACIÓN OK: criterios 1 a 3 y RLS de recompensas. (Este error deshace los datos de prueba.)';
end;
$$;
*/
