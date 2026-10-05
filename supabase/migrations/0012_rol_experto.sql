-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-227: desbloqueo del rol Runner Experto
--
-- El rol se gana al superar el décimo nivel, es decir, al haber
-- alcanzado el umbral de 11 niveles. Lo otorga la base, igual
-- que la XP (0009) y las insignias (0010): el cliente no escribe
-- en `roles_usuario`, solo lee lo suyo.
--
-- Decisiones:
--   - El requisito está en UN solo sitio, la constante de
--     `evaluar_rol_experto()`. Cambiarlo es otra migración con
--     `create or replace function`, no editar esta.
--   - Se evalúa en dos momentos, porque "niveles alcanzados"
--     puede subir por dos caminos: porque el corredor gana XP, o
--     porque el administrador crea un nivel con un umbral que ya
--     tenía superado.
--   - `on conflict do nothing` más el `unique (usuario_id, rol)`
--     de 0011: el rol se asigna una sola vez y `otorgado_en` no
--     se toca al volver a cumplir la condición (criterio 5).
--     Como `anunciado_en` tampoco cambia, no se vuelve a
--     anunciar.
--   - Un rol ganado no se quita si después baja la XP o se borra
--     un nivel: es el registro de un logro, como las insignias.
--
-- Corre esto DESPUÉS de 0011_roles_usuario.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La verificación
--
-- Otorga el rol a quien califique. Con `p_usuario` mira solo a
-- esa persona; sin él, a todas —lo que necesitan el trigger de
-- `niveles` y el backfill del final—.
--
-- Niveles alcanzados = los niveles cuyo umbral ya cubre la XP
-- acumulada. Es la misma cuenta que hace la app para decir en
-- qué nivel va alguien, así que las dos cuentan lo mismo.
--
-- `security definer` para poder escribir en `roles_usuario`, que
-- no tiene policy de insert a propósito.
-- -------------------------------------------------------------
create function public.evaluar_rol_experto(p_usuario uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  -- Superar el décimo nivel: estar en el 11, no en el 10.
  c_niveles_requeridos constant integer := 11;
begin
  insert into roles_usuario (usuario_id, rol)
  select acumulada.usuario_id, 'experto'
  from (
    select usuario_id, coalesce(sum(cantidad), 0)::integer as total
    from experiencia_ganada
    where p_usuario is null or usuario_id = p_usuario
    group by usuario_id
  ) as acumulada
  where (
    select count(*) from niveles
    where umbral_experiencia <= acumulada.total
  ) >= c_niveles_requeridos
  on conflict (usuario_id, rol) do nothing;
end;
$$;

revoke execute on function public.evaluar_rol_experto(uuid)
  from public, anon, authenticated;

-- -------------------------------------------------------------
-- 2. Al ganar experiencia
--
-- Tolerante a fallos por lo mismo que el trigger de insignias:
-- la XP la inserta `otorgar_experiencia` (0009) dentro de su
-- propio bloque `exception`, y si esto lanzara un error se
-- desharía también la XP del entrenamiento. Así solo se pierde
-- la evaluación del rol, queda un warning en los logs y se
-- vuelve a intentar con la siguiente XP que entre.
--
-- El bloqueo por usuario es el mismo de 0009 y 0010: dos cierres
-- a la vez no leen la misma suma.
-- -------------------------------------------------------------
create function public.otorgar_rol_experto()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  begin
    perform pg_advisory_xact_lock(hashtext(new.usuario_id::text));
    perform public.evaluar_rol_experto(new.usuario_id);
  exception when others then
    raise warning 'No se pudo evaluar el rol de experto del usuario %: % (%)',
      new.usuario_id, sqlerrm, sqlstate;
  end;

  return new;
end;
$$;

revoke execute on function public.otorgar_rol_experto()
  from public, anon, authenticated;

-- Una fila con 0 XP no cambia la acumulada: no hay nivel nuevo
-- que alcanzar.
create trigger otorgar_rol_experto_al_ganar_experiencia
  after insert on experiencia_ganada
  for each row
  when (new.cantidad > 0)
  execute function public.otorgar_rol_experto();

-- -------------------------------------------------------------
-- 3. Al crear un nivel
--
-- Un nivel nuevo con un umbral bajo sube los niveles alcanzados
-- de todo el mundo sin que nadie corra. Sin esto, quien ya
-- calificara tendría que esperar a su próximo entrenamiento para
-- recibir el rol.
--
-- `for each statement`: da igual cuántos niveles entren, la
-- evaluación mira la tabla completa una vez. Y tolerante a
-- fallos también: crear un nivel no puede fallar por esto.
-- -------------------------------------------------------------
create function public.otorgar_rol_experto_por_niveles()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  begin
    perform public.evaluar_rol_experto();
  exception when others then
    raise warning 'No se pudo evaluar el rol de experto tras crear un nivel: % (%)',
      sqlerrm, sqlstate;
  end;

  return null;
end;
$$;

revoke execute on function public.otorgar_rol_experto_por_niveles()
  from public, anon, authenticated;

create trigger otorgar_rol_experto_al_crear_nivel
  after insert on niveles
  for each statement
  execute function public.otorgar_rol_experto_por_niveles();

-- -------------------------------------------------------------
-- 4. Quien ya califica
--
-- Los corredores que a día de hoy ya superaron el décimo nivel
-- reciben el rol ahora, sin esperar su próxima actividad.
-- -------------------------------------------------------------
select public.evaluar_rol_experto();

-- -------------------------------------------------------------
-- 5. Comprobación
--
-- Para correr en el SQL Editor después de aplicar la migración.
-- Dice cuántos niveles hay creados, cuántos hacen falta y quién
-- tiene el rol. Si no hay 11 niveles, nadie puede desbloquearlo
-- todavía: eso no es un fallo de la migración.
-- -------------------------------------------------------------
-- select
--   (select count(*) from niveles)          as niveles_creados,
--   11                                      as niveles_requeridos,
--   (select count(*) from roles_usuario
--     where rol = 'experto')                as expertos;

-- -------------------------------------------------------------
-- 6. Prueba del desbloqueo (SCRUM-230)
--
-- Comprueba lo que no se puede probar desde Flutter, porque vive
-- en Postgres: que con 10 niveles alcanzados no se otorgue el
-- rol, que al llegar al 11 se otorgue solo, y que volver a
-- evaluar no cree otra fila ni mueva `otorgado_en` (criterio 5
-- de SCRUM-224).
--
-- Se descomenta, se pega entero en el SQL Editor y se corre. No
-- deja rastro: el bloque termina lanzando un error a propósito,
-- así que Postgres deshace todo lo que hizo. El resultado se lee
-- en el mensaje de ese error. Necesita un corredor con 11 o más
-- de XP acumulada.
-- -------------------------------------------------------------
-- do $$
-- declare
--   v_usuario   uuid;
--   v_filas     integer;
--   v_otorgado  timestamptz;
--   v_despues   timestamptz;
-- begin
--   select usuario_id into v_usuario
--   from experiencia_ganada
--   group by usuario_id
--   having sum(cantidad) >= 11
--   order by sum(cantidad) desc
--   limit 1;
--
--   if v_usuario is null then
--     raise exception 'Sin datos: nadie tiene 11 XP acumulada todavía.';
--   end if;
--
--   -- Escenario controlado; se deshace al final.
--   delete from roles_usuario where usuario_id = v_usuario;
--   delete from niveles;
--
--   insert into niveles (nombre, umbral_experiencia)
--   select 'Prueba ' || i, i from generate_series(1, 10) as i;
--   perform public.evaluar_rol_experto(v_usuario);
--
--   select count(*) into v_filas from roles_usuario
--   where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 0 then
--     raise exception 'FALLA: con 10 niveles alcanzados ya otorgó el rol.';
--   end if;
--
--   -- Sin llamar a nada: lo dispara el trigger de `niveles`.
--   insert into niveles (nombre, umbral_experiencia) values ('Prueba 11', 11);
--
--   select count(*), min(otorgado_en) into v_filas, v_otorgado
--   from roles_usuario where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 1 then
--     raise exception 'FALLA: al llegar a 11 niveles hay % filas de rol.', v_filas;
--   end if;
--
--   perform public.evaluar_rol_experto(v_usuario);
--   perform public.evaluar_rol_experto();
--
--   select count(*), min(otorgado_en) into v_filas, v_despues
--   from roles_usuario where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 1 then
--     raise exception 'FALLA: se duplicó el rol, hay % filas.', v_filas;
--   end if;
--   if v_despues <> v_otorgado then
--     raise exception 'FALLA: `otorgado_en` cambió al volver a evaluar.';
--   end if;
--
--   raise exception 'PRUEBA SUPERADA — no se otorga con 10, se otorga con 11, '
--     'y no se reasigna (no se guardó nada).';
-- end;
-- $$;
