-- =============================================================
-- TRAZA — Sprint 2 · SCRUM-227: desbloqueo del rol Runner Experto
--
-- El rol se gana cumpliendo tres cosas a la vez: haber superado
-- el décimo nivel, tener 150 000 de XP acumulada y 6 meses de
-- cuenta.
--
-- La XP y la antigüedad son las mismas que la app ya le muestra
-- al corredor en `RequisitosRunnerExperto` (SCRUM-210): si aquí
-- dijeran otra cosa, la pantalla prometería una y la base haría
-- otra. El nivel todavía no aparece en esa pantalla, aunque el
-- criterio 1 de SCRUM-195 lo pide; cuando se añada, tiene que
-- usar el mismo número de aquí.
--
-- Lo otorga la base, igual que la XP (0009) y las insignias
-- (0010): el cliente no escribe en `roles_usuario`, solo lee lo
-- suyo. Lo que vive solo en Dart no está validado —con la
-- publishable key cualquiera habla con Postgres—, así que esta
-- es la comprobación que vale.
--
-- Decisiones:
--   - Los tres requisitos están en UN solo sitio, las constantes
--     de `evaluar_rol_experto()`. Cambiarlos es otra migración
--     con `create or replace function`, no editar esta.
--   - Se evalúa en tres momentos, porque los requisitos se
--     cumplen de formas distintas: la XP entra como un evento
--     (trigger sobre `experiencia_ganada`), los niveles
--     alcanzados pueden subir porque el administrador cree uno
--     nuevo (trigger sobre `niveles`), y la antigüedad se cumple
--     sola con el paso del tiempo, que ningún trigger puede ver
--     —para eso está `evaluar_mi_rol_experto()`, que la app
--     llama al entrar—.
--   - `on conflict do nothing` más el `unique (usuario_id, rol)`
--     de 0011: el rol se asigna una sola vez y `otorgado_en` no
--     se toca al volver a cumplir la condición (criterio 5).
--     Como `anunciado_en` tampoco cambia, no se vuelve a
--     anunciar.
--   - Un rol ganado no se quita si después baja la XP: es el
--     registro de un logro, como las insignias.
--
-- Corre esto DESPUÉS de 0011_roles_usuario.sql.
-- =============================================================

-- -------------------------------------------------------------
-- 1. La verificación
--
-- Otorga el rol a quien califique. Con `p_usuario` mira solo a
-- esa persona; sin él, a todas —lo que necesita el backfill del
-- final—.
--
-- La antigüedad se cuenta desde `auth.users.created_at`, que es
-- la misma fecha que la app usa para decir cuántos días faltan.
-- Los niveles alcanzados son los que la XP acumulada ya cubre,
-- la misma cuenta que hace la app para decir en qué nivel va
-- alguien (SCRUM-178).
--
-- `security definer` para poder escribir en `roles_usuario`, que
-- no tiene policy de insert a propósito, y para leer
-- `auth.users`.
-- -------------------------------------------------------------
create function public.evaluar_rol_experto(p_usuario uuid default null)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  c_experiencia constant integer := 150000;
  c_meses       constant integer := 6;
  -- Superar el décimo nivel: estar en el 11, no en el 10.
  c_niveles     constant integer := 11;
begin
  insert into roles_usuario (usuario_id, rol)
  select acumulada.id, 'experto'
  from (
    select
      cuenta.id,
      cuenta.created_at,
      (
        select coalesce(sum(cantidad), 0)::integer
        from experiencia_ganada
        where usuario_id = cuenta.id
      ) as total
    from auth.users as cuenta
    where p_usuario is null or cuenta.id = p_usuario
  ) as acumulada
  -- Seis meses cumplidos, contados sobre el calendario.
  where acumulada.created_at <= now() - make_interval(months => c_meses)
    and acumulada.total >= c_experiencia
    and (
      select count(*) from niveles
      where umbral_experiencia <= acumulada.total
    ) >= c_niveles
  on conflict (usuario_id, rol) do nothing;
end;
$$;

revoke execute on function public.evaluar_rol_experto(uuid)
  from public, anon, authenticated;

-- -------------------------------------------------------------
-- 2. Al ganar experiencia
--
-- Cubre el requisito que entra como evento: cada vez que se
-- acredita XP se mira si con esa ya alcanza.
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

-- Una fila con 0 XP no cambia la acumulada: no hay nada nuevo
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
-- calificara tendría que esperar a su próximo entrenamiento.
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
-- 4. Al entrar a la app
--
-- El tercer requisito, la antigüedad, no entra como evento: se
-- cumple sola el día que la cuenta llega a los seis meses. Quien
-- ya tenga la XP y los niveles no recibiría el rol hasta su
-- siguiente entrenamiento, que podría ser mucho después.
--
-- Esta función deja que la app pida esa revisión al entrar. No
-- recibe el usuario: siempre es el de la sesión, así que nadie
-- puede evaluar —ni otorgar— por otra cuenta.
-- -------------------------------------------------------------
create function public.evaluar_mi_rol_experto()
returns void
language sql
security definer set search_path = public
as $$
  select public.evaluar_rol_experto(auth.uid());
$$;

revoke execute on function public.evaluar_mi_rol_experto() from public, anon;
grant execute on function public.evaluar_mi_rol_experto() to authenticated;

-- -------------------------------------------------------------
-- 5. Quien ya califica
--
-- Los corredores que a día de hoy ya cumplen los tres requisitos
-- reciben el rol ahora, sin esperar su próxima actividad.
-- -------------------------------------------------------------
select public.evaluar_rol_experto();

-- -------------------------------------------------------------
-- 6. Comprobación
--
-- Para correr en el SQL Editor después de aplicar la migración.
-- Dice cuántos tienen el rol y cómo va cada requisito por su
-- lado. Que todo sea cero no es un fallo: 150 000 XP son muchos
-- kilómetros, y ninguna cuenta tiene seis meses todavía.
-- -------------------------------------------------------------
-- select
--   (select count(*) from roles_usuario
--     where rol = 'experto')                           as expertos,
--   (select count(*) from auth.users
--     where created_at <= now() - interval '6 months')  as con_6_meses,
--   (select count(*) from niveles)                      as niveles_creados,
--   11                                                  as niveles_requeridos,
--   (select coalesce(max(total), 0) from (
--      select sum(cantidad) as total from experiencia_ganada
--      group by usuario_id) as sumas)                   as xp_mas_alta,
--   150000                                              as xp_requerida;

-- -------------------------------------------------------------
-- 7. Prueba del desbloqueo (SCRUM-230)
--
-- Comprueba lo que no se puede probar desde Flutter, porque vive
-- en Postgres: que falte cualquiera de los tres requisitos
-- impide el rol, que cumplirlos lo otorga, y que volver a
-- evaluar no crea otra fila ni mueve `otorgado_en` (criterio 5).
--
-- Se descomenta, se pega entero en el SQL Editor y se corre. No
-- deja rastro: el bloque termina lanzando un error a propósito,
-- así que Postgres deshace todo lo que hizo —incluidos los
-- retoques a la XP y a la fecha de la cuenta—. El resultado se
-- lee en el mensaje de ese error.
--
-- Necesita una cuenta con al menos una fila de XP.
-- -------------------------------------------------------------
-- do $$
-- declare
--   v_usuario   uuid;
--   v_fila      uuid;
--   v_filas     integer;
--   v_otorgado  timestamptz;
--   v_despues   timestamptz;
-- begin
--   select usuario_id, id into v_usuario, v_fila
--   from experiencia_ganada limit 1;
--
--   if v_usuario is null then
--     raise exception 'Sin datos: todavía nadie ha ganado XP.';
--   end if;
--
--   -- Escenario controlado; se deshace al final.
--   delete from roles_usuario where usuario_id = v_usuario;
--   delete from experiencia_ganada
--     where usuario_id = v_usuario and id <> v_fila;
--   delete from niveles;
--   insert into niveles (nombre, umbral_experiencia)
--   select 'Prueba ' || i, i * 1000 from generate_series(1, 11) as i;
--
--   -- 1. Niveles y antigüedad de sobra, pero sin la XP: no se otorga.
--   update auth.users set created_at = now() - interval '7 months'
--     where id = v_usuario;
--   update experiencia_ganada set cantidad = 11000 where id = v_fila;
--   perform public.evaluar_rol_experto(v_usuario);
--
--   select count(*) into v_filas from roles_usuario
--   where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 0 then
--     raise exception 'FALLA: otorgó el rol sin la XP suficiente.';
--   end if;
--
--   -- 2. XP y niveles de sobra, pero cuenta nueva: tampoco.
--   update auth.users set created_at = now() - interval '1 month'
--     where id = v_usuario;
--   update experiencia_ganada set cantidad = 150000 where id = v_fila;
--   perform public.evaluar_rol_experto(v_usuario);
--
--   select count(*) into v_filas from roles_usuario
--   where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 0 then
--     raise exception 'FALLA: otorgó el rol a una cuenta de un mes.';
--   end if;
--
--   -- 3. XP y antigüedad, pero solo 10 niveles alcanzados: tampoco.
--   update auth.users set created_at = now() - interval '7 months'
--     where id = v_usuario;
--   delete from niveles where umbral_experiencia = 11000;
--   insert into niveles (nombre, umbral_experiencia)
--     values ('Prueba alta', 999999);
--   perform public.evaluar_rol_experto(v_usuario);
--
--   select count(*) into v_filas from roles_usuario
--   where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 0 then
--     raise exception 'FALLA: otorgó el rol con solo 10 niveles alcanzados.';
--   end if;
--
--   -- 4. Los tres requisitos: ahora sí, y sin pedirlo —lo dispara
--   --    el trigger de `niveles`—.
--   insert into niveles (nombre, umbral_experiencia) values ('Prueba 11', 11000);
--
--   select count(*), min(otorgado_en) into v_filas, v_otorgado
--   from roles_usuario where usuario_id = v_usuario and rol = 'experto';
--   if v_filas <> 1 then
--     raise exception 'FALLA: cumpliendo todo hay % filas de rol.', v_filas;
--   end if;
--
--   -- 5. Volver a cumplir no reasigna.
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
--   raise exception 'PRUEBA SUPERADA — hacen falta los tres requisitos, '
--     'y el rol no se reasigna (no se guardó nada).';
-- end;
-- $$;
