-- =============================================================
-- TRAZA — Rutas oficiales, etapa 2 (docs/roadmap_mapa_rutas_oficiales.md)
--
-- El mapa de progresión pasa a mostrar las rutas oficiales
-- (0058) y, de cada una, si el corredor ya la completó. Esta
-- migración guarda qué rutas completó cada corredor.
--
-- Decisiones:
--
--   · Se guarda por ruta, no por posición. Si el administrador
--     reordena o quita una ruta del mapa, nadie pierde lo que ya
--     corrió: el mapa se recalcula a partir de esta tabla.
--
--   · Completar una ruta da ventaja (avanzar en el mapa), así que
--     el cliente solo lee. La llena `verificar_ruta_completada`
--     (etapa 4), que compara los puntos GPS del entrenamiento con
--     el trazado de la ruta. Hasta entonces la tabla queda vacía y
--     el mapa muestra todo "por recorrer".
--
--   · Sin políticas de escritura y sin el privilegio, como en
--     RNF-14 (0056): si mañana alguien escribe una policy de más,
--     el privilegio ya no está.
--
--   · Una fila por corredor y ruta: completarla otra vez no
--     duplica nada.
--
-- Corre esto DESPUÉS de 0058_rutas_oficiales.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La tabla
-- -------------------------------------------------------------
create table rutas_completadas (
  usuario_id        uuid not null references auth.users(id) on delete cascade,
  ruta_id           uuid not null references rutas(id) on delete cascade,
  -- El entrenamiento con el que se completó. Si llegara a borrarse,
  -- la ruta sigue completada.
  entrenamiento_id  uuid references entrenamientos(id) on delete set null,
  -- Qué parte del trazado se recorrió, de 0 a 1 (etapa 4).
  cobertura         numeric(4, 3) not null,
  fecha_completada  timestamptz not null default now(),
  primary key (usuario_id, ruta_id),
  constraint rutas_completadas_cobertura_valida
    check (cobertura between 0 and 1)
);

comment on table rutas_completadas is
  'Rutas que cada corredor completó. Solo la escribe la base '
  '(verificar_ruta_completada, etapa 4); el cliente solo lee las suyas.';

-- -------------------------------------------------------------
-- 2. RLS
--
-- Cada corredor ve solo las suyas. La policy filtra por
-- `usuario_id`, que es la primera columna de la clave primaria:
-- ya tiene índice.
-- -------------------------------------------------------------
alter table rutas_completadas enable row level security;

create policy "el corredor ve las rutas que completó"
  on rutas_completadas for select
  to authenticated
  using (auth.uid() = usuario_id);

revoke all on rutas_completadas from anon, authenticated;
grant select on rutas_completadas to authenticated;

-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea dos corredores, un autor y una ruta, le da a cada corredor
-- una ruta completada (como lo hará la etapa 4) y revisa el RLS.
-- Al final lanza un error A PROPÓSITO para que todo se deshaga.
-- El resultado es el mensaje de ese error:
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_autor    uuid := gen_random_uuid();
  v_ana      uuid := gen_random_uuid();
  v_beto     uuid := gen_random_uuid();
  v_tipo     uuid := (select id from tipos_actividad limit 1);
  v_e        uuid;
  v_ruta     uuid;
  v_n        integer;
  v_trazado  jsonb := '[{"lat": 6.2442, "lng": -75.5812},
                        {"lat": 6.2450, "lng": -75.5800}]';
begin
  insert into auth.users (id, email) values
    (v_autor, 'prueba-completadas-' || v_autor || '@traza.test'),
    (v_ana,   'prueba-completadas-' || v_ana   || '@traza.test'),
    (v_beto,  'prueba-completadas-' || v_beto  || '@traza.test');

  insert into entrenamientos (usuario_id, tipo_actividad_id, distancia_total_m, estado)
    values (v_autor, v_tipo, 3000, 'finalizado') returning id into v_e;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_autor, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into rutas (autor_id, entrenamiento_id, nombre, trazado)
    values (v_autor, v_e, 'Ruta completada', v_trazado) returning id into v_ruta;

  -- Lo que hará la etapa 4: la base registra que cada uno la completó.
  reset role;
  insert into rutas_completadas (usuario_id, ruta_id, cobertura)
    values (v_ana, v_ruta, 0.950), (v_beto, v_ruta, 1);

  -- Una fila por corredor y ruta.
  begin
    insert into rutas_completadas (usuario_id, ruta_id, cobertura)
      values (v_ana, v_ruta, 1);
    raise exception 'FALLÓ: se registró dos veces la misma ruta para un corredor';
  exception when unique_violation then null;
  end;

  -- La cobertura va de 0 a 1.
  begin
    insert into rutas_completadas (usuario_id, ruta_id, cobertura)
      values (v_autor, v_ruta, 1.5);
    raise exception 'FALLÓ: se guardó una cobertura mayor que 1';
  exception when check_violation then null;
  end;

  -- Ana ve solo la suya.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from rutas_completadas where ruta_id = v_ruta;
  if v_n <> 1 then
    raise exception 'FALLÓ: Ana ve % filas de esa ruta y debería ver solo la suya', v_n;
  end if;
  select count(*) into v_n from rutas_completadas where usuario_id = v_beto;
  if v_n <> 0 then raise exception 'FALLÓ: Ana ve lo que completó Beto'; end if;

  -- Ana no se marca rutas como completadas, ni las cambia, ni las borra.
  begin
    insert into rutas_completadas (usuario_id, ruta_id, cobertura)
      values (v_ana, v_ruta, 1);
    raise exception 'FALLÓ: un corredor escribió rutas_completadas directo';
  exception when insufficient_privilege then null;
  end;
  begin
    update rutas_completadas set cobertura = 1 where usuario_id = v_ana;
    raise exception 'FALLÓ: un corredor pudo hacer update directo';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from rutas_completadas where usuario_id = v_ana;
    raise exception 'FALLÓ: un corredor pudo hacer delete directo';
  exception when insufficient_privilege then null;
  end;

  -- Sin sesión no se lee nada.
  set local role anon;
  begin
    perform 1 from rutas_completadas limit 1;
    raise exception 'FALLÓ: anon puede leer rutas_completadas';
  exception when insufficient_privilege then null;
  end;

  raise exception 'VERIFICACIÓN OK: rutas_completadas cumple la etapa 2 (todo se deshace)';
end;
$$;
*/
