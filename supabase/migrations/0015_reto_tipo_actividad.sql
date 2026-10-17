-- =============================================================
-- TRAZA — Sprint 2: tipo de actividad en los retos
--
-- Un reto deja de ser "5 km" a secas y pasa a ser "5 km
-- corriendo" o "5 km caminando". Con eso, el corredor puede
-- llevar a la vez un reto diario, uno semanal y uno mensual de
-- cada tipo de actividad, pero no dos del mismo hueco.
--
-- Corre esto DESPUÉS de 0008_retos_usuario.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La columna
-- -------------------------------------------------------------
-- Nace aceptando nulos porque ya hay retos creados: primero se
-- añade, luego se rellenan y al final se exige.
alter table retos
  add column tipo_actividad_id uuid references tipos_actividad(id);

-- Los retos que ya existían se quedan en Correr: es el tipo por
-- defecto del catálogo y ninguno se creó pensando en caminar.
update retos
set tipo_actividad_id = (select id from tipos_actividad where nombre = 'Correr')
where tipo_actividad_id is null;

alter table retos
  alter column tipo_actividad_id set not null;

-- Sin `on delete cascade` ni `set null`: tipos_actividad no tiene
-- policy de escritura, así que nadie borra desde el cliente. Si
-- algún día se borrara desde el dashboard, esto lo impediría en
-- vez de dejar retos sin tipo.

-- Para la comprobación de la regla, que filtra por tipo y
-- periodicidad.
create index retos_tipo_periodicidad_idx
  on retos (tipo_actividad_id, periodicidad);

-- -------------------------------------------------------------
-- 2. Un reto por hueco
-- -------------------------------------------------------------
-- El hueco es la pareja (periodicidad, tipo de actividad): un
-- diario de Correr y un diario de Caminar conviven, dos diarios
-- de Correr no.
--
-- Va en un trigger y no en un índice único porque la
-- periodicidad y el tipo viven en `retos`, no en
-- `retos_usuario`, y un índice no puede mirar otra tabla. La
-- alternativa era copiar las dos columnas a `retos_usuario`, y
-- un dato duplicado que nadie vuelve a mirar se desincroniza
-- solo.
--
-- Lo que compara son las fechas de vigencia, no el día de hoy:
-- dos retos diarios del mismo tipo chocan si son del mismo día,
-- pero el de mañana no choca con el de hoy. Así la regla no
-- necesita saber en qué día vive el teléfono, que es justo lo
-- que la base no puede saber estando en UTC.
create or replace function impedir_reto_del_mismo_hueco()
returns trigger
language plpgsql
-- `security definer`: la comprobación tiene que ver todas las
-- filas del corredor, no las que RLS le deje ver en ese momento.
-- Un reto invisible para la consulta sería un hueco libre que no
-- lo está.
security definer
set search_path = public
as $$
declare
  en_curso text;
  actividad text;
begin
  select r_otro.nombre, t.nombre
    into en_curso, actividad
  from retos_usuario ru_otro
  join retos r_otro on r_otro.id = ru_otro.reto_id
  join retos r_nuevo on r_nuevo.id = new.reto_id
  join tipos_actividad t on t.id = r_nuevo.tipo_actividad_id
  where ru_otro.usuario_id = new.usuario_id
    and ru_otro.id is distinct from new.id
    -- Lo completado no ocupa hueco: ya se cumplió.
    and ru_otro.estado = 'en_progreso'
    and r_otro.periodicidad = r_nuevo.periodicidad
    and r_otro.tipo_actividad_id = r_nuevo.tipo_actividad_id
    and daterange(r_otro.fecha_inicio, r_otro.fecha_fin, '[]')
        && daterange(r_nuevo.fecha_inicio, r_nuevo.fecha_fin, '[]')
  limit 1;

  if en_curso is not null then
    -- 23P01 (exclusion_violation) y no 23505: el cliente tiene
    -- que distinguir "ya activaste este reto" de "ya tienes otro
    -- en este hueco", que se dicen distinto.
    raise exception
      'ya hay un reto % en curso para %', en_curso, actividad
      using errcode = '23P01';
  end if;

  return new;
end;
$$;

create trigger retos_usuario_un_reto_por_hueco
  before insert on retos_usuario
  for each row
  execute function impedir_reto_del_mismo_hueco();
