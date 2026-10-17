-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-192: la XP sale solo de los retos
--
-- El entrenamiento libre deja de dar XP. Correr sigue sumando,
-- pero a los retos activos: completar un reto es la única forma
-- de ganar experiencia. Con esto cambian tres cosas:
--
--   1. `otorgar_experiencia()` (0009) ya no paga la actividad.
--      Desaparecen la tarifa por km, el mínimo de 1 km y el tope
--      diario: existían solo para esa XP. Se quedan las dos
--      validaciones de plausibilidad (sin datos, más de 25 km/h),
--      que ahora deciden si los km cuentan para los retos.
--
--   2. Los km avanzan solo los retos del mismo tipo de actividad
--      del entrenamiento. Desde 0015 cada reto es "X km corriendo"
--      o "X km caminando", pero el trigger de 0009 es anterior y
--      avanzaba todos: una caminata completaba un reto de correr.
--      Siendo los retos la única fuente de XP, eso era la vía
--      directa para cobrar sin hacer lo que el reto pide.
--
--   3. La meta de un reto tiene que quedar por encima de lo que
--      lleva cada corredor, no a la par. 0017 comparaba contra el
--      progreso redondeado a dos decimales y dejaba pasar la meta
--      igual: con 9,994 km hechos se podía poner 9,99, y con 10 de
--      10 también. El reto se completa con `progreso >= meta`, así
--      que ese corredor quedaba con el reto cumplido, en curso y
--      sin cobrar, esperando una carrera más antes de `fecha_fin`.
--      Es el agujero que 0017 quería cerrar.
--
--      No se le abre una salida (completar y pagar el reto al
--      bajar la meta): toda XP nace de un entrenamiento
--      (`experiencia_ganada.entrenamiento_id not null`), y un
--      segundo sitio que completa retos duplicaría el bloqueo, la
--      regla y los avisos. Es más sólido que ese estado no pueda
--      existir.
--
-- La XP de actividad ya ganada se conserva: borrarla bajaría el
-- nivel de quien ya tiene insignias o rol ganados con ella. La
-- regla nueva rige para los entrenamientos que se finalicen
-- desde ahora.
--
-- Reemplaza funciones de 0009 y 0017 con `create or replace`: los
-- triggers que las llaman siguen en pie y no se recrean.
--
-- Corre esto DESPUÉS de 0017_meta_no_baja_del_progreso.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1 y 2. otorgar_experiencia(): sin XP de actividad, retos por
--        tipo de actividad
--
-- La fila de 'actividad' se sigue escribiendo, con 0 XP: es la
-- marca de "ya procesado" que impide que un entrenamiento que se
-- vuelva a finalizar sume sus km dos veces a los retos. Su
-- `ajuste` le dice al resumen si los km contaron:
--   - 'ninguno': contaron para los retos.
--   - 'sin_datos' / 'velocidad_imposible': no contaron.
-- 'menos_del_minimo' y 'tope_diario' quedan solo en filas
-- anteriores a esta migración.
--
-- Sigue siendo tolerante a fallos, por lo mismo que en 0009:
-- perder una carrera es peor que perder su avance en los retos.
--
-- Reglas, iguales a ReglaExperiencia en Dart:
--   - sin distancia o sin duración: no cuenta
--   - promedio > 25 km/h: no cuenta (carro o bici)
-- -------------------------------------------------------------
create or replace function public.otorgar_experiencia()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  -- Constante de ReglaExperiencia.
  velocidad_maxima    constant numeric := 25;  -- km/h

  v_dia        date;
  v_distancia  numeric := new.distancia_total_m;
  v_duracion   integer := new.duracion_segundos;
  v_ajuste     text;
  v_km         numeric;
  v_reto       record;
begin
  -- Un cierre a la vez por usuario: es el mismo bloqueo de las
  -- insignias (0010) y del rol (0012), que leen la XP acumulada
  -- cuando entra la de un reto.
  perform pg_advisory_xact_lock(hashtext(new.usuario_id::text));

  begin
    if exists (
      select 1 from experiencia_ganada
      where entrenamiento_id = new.id and origen = 'actividad'
    ) then
      return new;
    end if;

    v_dia := (coalesce(new.fecha_fin, now()) at time zone 'America/Bogota')::date;

    if v_distancia is null or v_distancia <= 0
       or v_duracion is null or v_duracion <= 0 then
      v_ajuste := 'sin_datos';
    -- km/h = metros × 3.6 / segundos, comparado sin dividir.
    elsif v_distancia * 3.6 > velocidad_maxima * v_duracion then
      v_ajuste := 'velocidad_imposible';
    else
      v_ajuste := 'ninguno';
    end if;

    insert into experiencia_ganada
      (usuario_id, entrenamiento_id, origen, cantidad, metros_contados, ajuste, dia)
    values
      (new.usuario_id, new.id, 'actividad', 0, 0, v_ajuste, v_dia);

    if v_ajuste <> 'ninguno' then
      return new;
    end if;

    v_km := v_distancia / 1000;

    -- Solo los retos activados antes de finalizar, vigentes ese
    -- día, que el admin no haya retirado y del mismo tipo de
    -- actividad que el entrenamiento.
    for v_reto in
      select ru.id, ru.progreso_km, r.meta_km, r.xp_otorgada
      from retos_usuario ru
      join retos r on r.id = ru.reto_id
      where ru.usuario_id = new.usuario_id
        and ru.estado = 'en_progreso'
        and r.estado = 'activo'
        and r.tipo_actividad_id = new.tipo_actividad_id
        and v_dia between r.fecha_inicio and r.fecha_fin
      for update of ru
    loop
      if v_reto.progreso_km + v_km >= v_reto.meta_km then
        update retos_usuario
        set progreso_km = progreso_km + v_km,
            estado = 'completado',
            fecha_completado = coalesce(new.fecha_fin, now())
        where id = v_reto.id;

        insert into experiencia_ganada
          (usuario_id, entrenamiento_id, origen, reto_usuario_id, cantidad, dia)
        values
          (new.usuario_id, new.id, 'reto', v_reto.id, v_reto.xp_otorgada, v_dia);
      else
        update retos_usuario
        set progreso_km = progreso_km + v_km
        where id = v_reto.id;
      end if;
    end loop;
  exception when others then
    raise warning 'No se pudo procesar la XP del entrenamiento %: % (%)',
      new.id, sqlerrm, sqlstate;
  end;

  return new;
end;
$$;

-- -------------------------------------------------------------
-- 3. La meta queda por encima de lo que lleva cada corredor
--
-- Igual a la de 0017 salvo la última comparación. Se compara con
-- el progreso real, sin redondear: cualquier meta que no lo
-- supere deja el reto cumplido y sin cobrar. El mensaje lo
-- muestra redondeado, como lo pinta la app; por eso dice "por
-- encima": que rechace el mismo número que se ve es lo correcto.
-- -------------------------------------------------------------
create or replace function impedir_cambios_que_mueven_el_reto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_llevado numeric;
begin
  if new.periodicidad is distinct from old.periodicidad then
    raise exception 'la periodicidad de un reto no se cambia'
      using errcode = '23514';
  end if;

  if new.tipo_actividad_id is distinct from old.tipo_actividad_id then
    raise exception 'el tipo de actividad de un reto no se cambia'
      using errcode = '23514';
  end if;

  if new.fecha_inicio is distinct from old.fecha_inicio then
    raise exception 'la fecha de inicio de un reto no se cambia'
      using errcode = '23514';
  end if;

  if new.fecha_fin < old.fecha_fin then
    raise exception 'la fecha de fin solo se puede extender'
      using errcode = '23514';
  end if;

  -- Solo al bajarla: subir la meta no deja a nadie pasado.
  if new.meta_km < old.meta_km then
    -- Sin filtrar por fecha, por lo mismo que en 0017: la base
    -- corre en UTC y no sabe qué día es en el teléfono de nadie.
    select max(progreso_km) into v_llevado
    from retos_usuario
    where reto_id = old.id
      and estado = 'en_progreso';

    if v_llevado is not null and new.meta_km <= v_llevado then
      raise exception
        'hay un corredor con % km hechos: la meta tiene que quedar por encima',
        round(v_llevado, 2)
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;


-- =============================================================
-- VERIFICACIÓN (correr en el SQL Editor DESPUÉS de aplicar esta
-- migración, como un script aparte)
--
-- Crea un usuario de prueba, retos de Correr y de Caminar, y
-- revisa las tres reglas. Al final lanza un error A PROPÓSITO
-- para que todo se deshaga: no deja nada en la base.
--   - "VERIFICACIÓN OK: ..."  → todo cumple.
--   - "FALLÓ ...: ..."        → eso no cumple.
-- =============================================================
/*
do $$
declare
  v_usuario   uuid := gen_random_uuid();
  v_correr    uuid := (select id from tipos_actividad where nombre = 'Correr');
  v_caminar   uuid := (select id from tipos_actividad where nombre = 'Caminar');
  v_hoy       date := (now() at time zone 'America/Bogota')::date;
  v_reto_c    uuid;
  v_reto_w    uuid;
  v_ru_c      uuid;
  v_ru_w      uuid;
  v_ent       uuid;
  v_fila      record;
  v_rechazo   boolean;
begin
  insert into auth.users (id, email) values (v_usuario, v_usuario || '@prueba.traza');

  -- Retos diarios de 5 km que pagan 100 XP, uno por tipo.
  insert into retos (nombre, descripcion, meta_km, xp_otorgada, periodicidad, fecha_inicio,
                     fecha_fin, estado, tipo_actividad_id)
  values ('Prueba correr', 'Prueba', 5, 100, 'diaria', v_hoy, v_hoy, 'activo', v_correr)
  returning id into v_reto_c;
  insert into retos (nombre, descripcion, meta_km, xp_otorgada, periodicidad, fecha_inicio,
                     fecha_fin, estado, tipo_actividad_id)
  values ('Prueba caminar', 'Prueba', 5, 100, 'diaria', v_hoy, v_hoy, 'activo', v_caminar)
  returning id into v_reto_w;

  insert into retos_usuario (usuario_id, reto_id, estado, progreso_km)
  values (v_usuario, v_reto_c, 'en_progreso', 0) returning id into v_ru_c;
  insert into retos_usuario (usuario_id, reto_id, estado, progreso_km)
  values (v_usuario, v_reto_w, 'en_progreso', 0) returning id into v_ru_w;

  -- 1. Un entrenamiento libre de 3 km caminando: 0 XP de actividad.
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado)
  values (v_usuario, v_caminar, 'en_curso') returning id into v_ent;
  update entrenamientos
  set estado = 'finalizado', distancia_total_m = 3000, duracion_segundos = 1800,
      fecha_fin = now()
  where id = v_ent;

  select * into v_fila from experiencia_ganada
  where entrenamiento_id = v_ent and origen = 'actividad';
  if v_fila.cantidad is distinct from 0 or v_fila.ajuste is distinct from 'ninguno' then
    raise exception 'FALLÓ actividad: se esperaba 0 XP y ajuste ninguno, hay % / %',
      v_fila.cantidad, v_fila.ajuste;
  end if;

  -- 2. La caminata avanza el reto de caminar y no el de correr.
  if (select progreso_km from retos_usuario where id = v_ru_w) <> 3
     or (select progreso_km from retos_usuario where id = v_ru_c) <> 0 then
    raise exception 'FALLÓ tipo de actividad: caminar % km, correr % km',
      (select progreso_km from retos_usuario where id = v_ru_w),
      (select progreso_km from retos_usuario where id = v_ru_c);
  end if;

  -- Re-finalizar no suma dos veces.
  update entrenamientos set estado = 'en_curso' where id = v_ent;
  update entrenamientos set estado = 'finalizado' where id = v_ent;
  if (select progreso_km from retos_usuario where id = v_ru_w) <> 3 then
    raise exception 'FALLÓ re-finalizar: sumó dos veces';
  end if;

  -- Completar el reto paga su XP, y es la única XP.
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado)
  values (v_usuario, v_caminar, 'en_curso') returning id into v_ent;
  update entrenamientos
  set estado = 'finalizado', distancia_total_m = 2500, duracion_segundos = 1500,
      fecha_fin = now()
  where id = v_ent;
  if (select estado from retos_usuario where id = v_ru_w) <> 'completado'
     or (select coalesce(sum(cantidad), 0) from experiencia_ganada
         where usuario_id = v_usuario) <> 100 then
    raise exception 'FALLÓ reto: estado %, XP total %',
      (select estado from retos_usuario where id = v_ru_w),
      (select coalesce(sum(cantidad), 0) from experiencia_ganada where usuario_id = v_usuario);
  end if;

  -- A velocidad de carro no cuenta para los retos.
  insert into entrenamientos (usuario_id, tipo_actividad_id, estado)
  values (v_usuario, v_correr, 'en_curso') returning id into v_ent;
  update entrenamientos
  set estado = 'finalizado', distancia_total_m = 10000, duracion_segundos = 600,
      fecha_fin = now()
  where id = v_ent;
  if (select progreso_km from retos_usuario where id = v_ru_c) <> 0 then
    raise exception 'FALLÓ velocidad: el reto de correr avanzó';
  end if;

  -- 3. Con 4,994 km hechos, la meta no puede quedar en 4,99 ni en 4,994.
  update retos_usuario set progreso_km = 4.994 where id = v_ru_c;

  v_rechazo := false;
  begin
    update retos set meta_km = 4.99 where id = v_reto_c;
  exception when check_violation then v_rechazo := true;
  end;
  if not v_rechazo then
    raise exception 'FALLÓ meta: aceptó 4,99 con 4,994 hechos';
  end if;

  v_rechazo := false;
  begin
    update retos set meta_km = 4.994 where id = v_reto_c;
  exception when check_violation then v_rechazo := true;
  end;
  if not v_rechazo then
    raise exception 'FALLÓ meta: aceptó la meta igual al progreso';
  end if;

  update retos set meta_km = 5 - 0.001 where id = v_reto_c;  -- 4,999: por encima

  raise exception 'VERIFICACIÓN OK: actividad sin XP, retos por tipo, meta por encima';
end;
$$;
*/
