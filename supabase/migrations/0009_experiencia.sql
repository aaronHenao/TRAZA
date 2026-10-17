-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-192: ganancia de experiencia (XP)
--
-- La XP nace al finalizar un entrenamiento y sale de dos
-- fuentes: la actividad en sí (poca, SCRUM-202/203) y los retos
-- que ese entrenamiento complete (la mayor parte, SCRUM-205).
--
-- La asigna la base, no la app: el cliente no manda cantidades
-- y no puede escribir en `experiencia_ganada`. Las reglas están
-- repetidas en `lib/models/regla_experiencia.dart` para probarlas
-- y explicarlas en pantalla; si cambia una constante, cambia en
-- los dos lados.
--
-- Sin backfill: los entrenamientos finalizados antes de esta
-- migración no dan XP. Todos arrancan en cero.
--
-- Corre esto DESPUÉS de 0007_retos_usuario.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La tabla
--
-- La XP no va en `perfiles`: su policy deja al usuario cambiar
-- cualquier columna de su fila (ver docs/deudas.md). Aquí el
-- cliente solo lee.
--
-- No se guarda un total: se suma. Así no hay un acumulado que
-- se pueda desincronizar de sus movimientos.
-- -------------------------------------------------------------
create table experiencia_ganada (
  id                uuid primary key default gen_random_uuid(),
  usuario_id        uuid not null references auth.users(id) on delete cascade,
  -- Toda XP nace al finalizar un entrenamiento, también la de
  -- los retos. Si el usuario borra el entrenamiento, se lleva
  -- su XP: solo se perjudica a sí mismo.
  entrenamiento_id  uuid not null references entrenamientos(id) on delete cascade,
  origen            text not null,
  -- Solo para origen 'reto': cuál completó.
  reto_usuario_id   uuid references retos_usuario(id) on delete cascade,
  cantidad          integer not null,
  -- Solo para origen 'actividad': los metros que entraron al
  -- cálculo tras el mínimo, la velocidad y el tope. Se suman
  -- para saber cuánto tope le queda al usuario en el día.
  metros_contados   numeric,
  -- Solo para origen 'actividad': por qué dio menos de lo que
  -- daría su distancia completa. Es `AjusteExperiencia` en Dart;
  -- con esto el resumen explica el resultado sin recalcularlo.
  ajuste            text,
  -- Día en hora de Colombia al que cuenta para el tope diario.
  dia               date not null,
  fecha             timestamptz not null default now()
);

alter table experiencia_ganada
  add constraint experiencia_ganada_origen_valido
    check (origen in ('actividad', 'reto')),

  -- Cero es válido: una actividad que no dio XP también se
  -- registra, porque su fila es la marca de "ya procesado".
  add constraint experiencia_ganada_cantidad_no_negativa
    check (cantidad >= 0),

  add constraint experiencia_ganada_ajuste_valido
    check (ajuste is null or ajuste in (
      'ninguno', 'sin_datos', 'velocidad_imposible',
      'menos_del_minimo', 'tope_diario'
    )),

  -- Cada origen trae lo suyo y nada del otro.
  add constraint experiencia_ganada_forma_por_origen
    check (
      (origen = 'actividad'
        and reto_usuario_id is null
        and metros_contados is not null and metros_contados >= 0
        and ajuste is not null)
      or
      (origen = 'reto'
        and reto_usuario_id is not null
        and metros_contados is null
        and ajuste is null)
    );

-- -------------------------------------------------------------
-- 2. Índices
-- -------------------------------------------------------------

-- Un entrenamiento se procesa una sola vez. Un cliente que lo
-- vuelva a finalizar no cobra dos veces.
create unique index experiencia_ganada_una_por_entrenamiento_idx
  on experiencia_ganada (entrenamiento_id)
  where origen = 'actividad';

-- Un reto paga una sola vez.
create unique index experiencia_ganada_una_por_reto_idx
  on experiencia_ganada (reto_usuario_id)
  where origen = 'reto';

-- Lo que consulta el trigger en cada cierre: los metros del día.
create index experiencia_ganada_por_usuario_y_dia_idx
  on experiencia_ganada (usuario_id, dia);

-- -------------------------------------------------------------
-- 3. RLS
--
-- Solo lectura de lo propio. Sin policies de insert, update ni
-- delete: escribe únicamente el trigger, que es security
-- definer.
-- -------------------------------------------------------------
alter table experiencia_ganada enable row level security;

create policy "usuario ve su propia experiencia"
  on experiencia_ganada
  for select
  using (auth.uid() = usuario_id);

-- -------------------------------------------------------------
-- 4. retos_usuario: el progreso lo escribe solo la base
--
-- La policy `for all` de 0007_retos_usuario.sql dejaba al
-- usuario marcar un reto como completado a mano, y con eso
-- cobrar su XP. Ahora el usuario ve sus retos y los activa; el
-- progreso y el completado los escribe el trigger de abajo.
--
-- Si SCRUM-136 necesita abandonar un reto, que sea una policy
-- de delete o una función aparte, no un update libre.
-- -------------------------------------------------------------
drop policy "usuario gestiona sus propios retos" on retos_usuario;

create policy "usuario ve sus propios retos"
  on retos_usuario
  for select
  using (auth.uid() = usuario_id);

-- Activar es empezar de cero: nada de llegar ya con progreso o
-- ya completado.
create policy "usuario activa sus propios retos"
  on retos_usuario
  for insert
  with check (
    auth.uid() = usuario_id
    and estado = 'en_progreso'
    and progreso_km = 0
    and fecha_completado is null
  );

-- -------------------------------------------------------------
-- 5. El trigger: XP al finalizar
--
-- Es trigger y no una función que llame la app: la XP se
-- procesa en el mismo cierre y no se puede pedir aparte.
--
-- Tolerante a fallos: si algo de la XP falla, se deshace solo la
-- XP (el bloque `exception`) y el entrenamiento se cierra igual.
-- Perder una carrera es peor que perder su XP. El fallo queda
-- como warning en los logs de Postgres, y el entrenamiento, sin
-- fila de actividad en `experiencia_ganada`: así se encuentra y
-- se le puede calcular después.
--
-- Reglas (SCRUM-202), iguales a ReglaExperiencia en Dart:
--   - sin distancia o sin duración: 0 XP
--   - promedio > 25 km/h: 0 XP (carro o bici)
--   - menos de 1 km: 0 XP
--   - tope de 25 km por día en hora de Colombia
--   - 1 XP por cada 200 m completos (5 XP por km)
-- -------------------------------------------------------------
create function public.otorgar_experiencia()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  -- Constantes de ReglaExperiencia.
  metros_por_xp       constant numeric := 200;
  distancia_minima    constant numeric := 1000;
  tope_diario         constant numeric := 25000;
  velocidad_maxima    constant numeric := 25;  -- km/h

  v_dia        date;
  v_distancia  numeric := new.distancia_total_m;
  v_duracion   integer := new.duracion_segundos;
  v_hoy        numeric;
  v_disponible numeric;
  v_contados   numeric := 0;
  v_ajuste     text;
  v_km         numeric;
  v_reto       record;
begin
  -- Un cierre a la vez por usuario: dos entrenamientos que se
  -- finalizan juntos no pueden leer el mismo tope disponible.
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
    elsif v_distancia < distancia_minima then
      v_ajuste := 'menos_del_minimo';
    else
      select coalesce(sum(metros_contados), 0) into v_hoy
      from experiencia_ganada
      where usuario_id = new.usuario_id
        and dia = v_dia
        and origen = 'actividad';

      v_disponible := tope_diario - v_hoy;

      if v_disponible <= 0 then
        v_ajuste := 'tope_diario';
      elsif v_distancia > v_disponible then
        v_contados := v_disponible;
        v_ajuste := 'tope_diario';
      else
        v_contados := v_distancia;
        v_ajuste := 'ninguno';
      end if;
    end if;

    insert into experiencia_ganada
      (usuario_id, entrenamiento_id, origen, cantidad, metros_contados, ajuste, dia)
    values
      (new.usuario_id, new.id, 'actividad',
       floor(v_contados / metros_por_xp)::integer, v_contados, v_ajuste, v_dia);

    -- Retos (SCRUM-205). Sin datos o a velocidad de carro, los km
    -- no son de alguien corriendo: tampoco avanzan retos. Sí
    -- avanzan con menos de 1 km o con el tope lleno: el tope es de
    -- la XP de actividad, no del esfuerzo.
    if v_ajuste in ('sin_datos', 'velocidad_imposible') then
      return new;
    end if;

    v_km := v_distancia / 1000;

    -- Solo los retos activados antes de finalizar (los demás no
    -- existen todavía), vigentes ese día y que el admin no haya
    -- retirado.
    for v_reto in
      select ru.id, ru.progreso_km, r.meta_km, r.xp_otorgada
      from retos_usuario ru
      join retos r on r.id = ru.reto_id
      where ru.usuario_id = new.usuario_id
        and ru.estado = 'en_progreso'
        and r.estado = 'activo'
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
    raise warning 'No se pudo otorgar XP al entrenamiento %: % (%)',
      new.id, sqlerrm, sqlstate;
  end;

  return new;
end;
$$;

-- Solo en el paso a finalizado. Un entrenamiento cancelado no da
-- nada, y uno que se vuelva a finalizar lo frena la comprobación
-- de arriba.
create trigger otorgar_experiencia_al_finalizar
  after update of estado on entrenamientos
  for each row
  when (new.estado = 'finalizado' and old.estado is distinct from 'finalizado')
  execute function public.otorgar_experiencia();

-- -------------------------------------------------------------
-- 6. experiencia_total(): la XP acumulada del usuario
--
-- `security invoker` (el default): corre con el RLS del usuario,
-- que de todas formas solo ve lo suyo.
-- -------------------------------------------------------------
create function public.experiencia_total()
returns integer
language sql
stable
as $$
  select coalesce(sum(cantidad), 0)::integer
  from public.experiencia_ganada
  where usuario_id = auth.uid();
$$;
