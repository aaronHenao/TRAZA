-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-256 (HU-30): buscar por creador sin
-- confundir personas
--
-- 0040 busca cada palabra en cualquier parte del nombre de la
-- ruta y de quien la creó. Para personas eso falla: "ana" también
-- encuentra a Mariana, a Juliana y a Diana, y el criterio 3 de
-- HU-30 pide "las rutas creadas por esa persona".
--
-- Decisiones:
--
--   · Por inicio de palabra, no en cualquier parte: "ana"
--     encuentra a Ana y a Ana María, no a Mariana. Mientras se
--     escribe sigue funcionando, porque cada palabra se busca por
--     su comienzo: "nuti" ya encuentra "Subida al Nutibara".
--
--   · Lo que no es letra ni número separa palabras. Así
--     "Laureles-Estadio" son dos, y "estadio" la encuentra; antes
--     solo contaban los espacios. Por lo mismo, "%" y "_" ya no se
--     buscan: lo escrito que no tenga al menos dos letras o números
--     se rechaza, como antes lo que tenía menos de dos caracteres.
--
--   · Nada más cambia. Mismos parámetros, mismas columnas, mismo
--     orden y mismo filtro por zona: por eso alcanza con `create
--     or replace`, que conserva los permisos que dejó 0040 (solo
--     con sesión).
--
-- Lo que NO hace esta migración:
--
--   · No toca `autor_nombre`: sigue siendo el nombre que tenía el
--     autor al publicar (0029). Si después lo cambia en su perfil,
--     sus rutas viejas se encuentran por el nombre de entonces, que
--     es también el que muestra la tarjeta.
--
-- Corre esto DESPUÉS de 0040_buscar_rutas.sql.
-- =============================================================

begin;

-- -------------------------------------------------------------
-- Un texto como se compara al buscar
--
-- Igual que en 0040 —sin tildes, en minúsculas, la ñ como n—,
-- salvo que ahora todo lo que no es letra ni número se vuelve un
-- espacio: guiones, paréntesis, comas, signos.
-- -------------------------------------------------------------
create or replace function public.texto_para_buscar(p_texto text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select btrim(regexp_replace(
    lower(translate(
      coalesce(p_texto, ''),
      'ÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇáàäâãéèëêíìïîóòöôõúùüûñç',
      'AAAAAEEEEIIIIOOOOOUUUUNCaaaaaeeeeiiiiooooouuuunc'
    )),
    '[^a-z0-9]+', ' ', 'g'
  ));
$$;

comment on function public.texto_para_buscar(text) is
  'Un texto sin tildes, en minúsculas y con solo letras y números separados por un espacio, para comparar al buscar (SCRUM-253 y SCRUM-256).';

-- -------------------------------------------------------------
-- Las rutas publicadas que coinciden con una búsqueda
--
-- La de 0040 con un solo cambio: cada palabra escrita tiene que
-- ser el comienzo de alguna palabra del nombre o del creador.
-- -------------------------------------------------------------
create or replace function public.buscar_rutas(
  p_termino    text,
  p_latitud    double precision default null,
  p_longitud   double precision default null,
  p_zona_sur   double precision default null,
  p_zona_oeste double precision default null,
  p_zona_norte double precision default null,
  p_zona_este  double precision default null,
  p_limite     integer default 50
)
returns table (
  id                   uuid,
  autor_id             uuid,
  autor_nombre         text,
  entrenamiento_id     uuid,
  nombre               text,
  descripcion          text,
  distancia_km         numeric,
  estado               text,
  motivo_rechazo       text,
  fecha_creacion       timestamptz,
  fecha_publicacion    timestamptz,
  distancia_usuario_km double precision,
  miniatura            jsonb
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_termino     text := public.texto_para_buscar(p_termino);
  v_palabras    text[] := '{}';
  v_con_texto   boolean;
  v_con_zona    boolean;
  v_con_usuario boolean;
  v_limite      integer;
begin
  if num_nonnulls(p_zona_sur, p_zona_oeste, p_zona_norte, p_zona_este)
     not in (0, 4) then
    raise exception 'la zona necesita sus cuatro bordes'
      using errcode = '22023';
  end if;
  v_con_zona := p_zona_sur is not null;

  if v_con_zona and (
       p_zona_sur not between -90 and 90
    or p_zona_norte not between -90 and 90
    or p_zona_oeste not between -180 and 180
    or p_zona_este not between -180 and 180
    or p_zona_sur > p_zona_norte
    or p_zona_oeste > p_zona_este
  ) then
    raise exception 'zona fuera de rango: sur %, oeste %, norte %, este %',
      p_zona_sur, p_zona_oeste, p_zona_norte, p_zona_este
      using errcode = '22023';
  end if;

  if num_nonnulls(p_latitud, p_longitud) = 1
     or (p_latitud is not null and (
          p_latitud not between -90 and 90
       or p_longitud not between -180 and 180
     )) then
    raise exception 'coordenadas fuera de rango: (%, %)',
      p_latitud, p_longitud
      using errcode = '22023';
  end if;
  v_con_usuario := p_latitud is not null;

  v_con_texto := length(v_termino) >= 2;
  if v_con_texto then
    v_palabras := string_to_array(v_termino, ' ');
  end if;

  if not v_con_texto and not v_con_zona then
    raise exception
      'nada que buscar: hacen falta al menos dos letras o una zona'
      using errcode = '22023';
  end if;

  v_limite := least(greatest(coalesce(p_limite, 50), 1), 100);

  return query
  select
    c.id,
    c.autor_id,
    c.autor_nombre,
    c.entrenamiento_id,
    c.nombre,
    c.descripcion,
    c.distancia_km,
    c.estado,
    c.motivo_rechazo,
    c.fecha_creacion,
    c.fecha_publicacion,
    c.distancia_usuario_km,
    c.miniatura
  from (
    select
      r.id,
      r.autor_id,
      r.autor_nombre,
      r.entrenamiento_id,
      r.nombre,
      r.descripcion,
      r.distancia_km,
      r.estado,
      r.motivo_rechazo,
      r.fecha_creacion,
      r.fecha_publicacion,
      case when v_con_usuario then
        public.distancia_km_entre(
          p_latitud, p_longitud, r.inicio_latitud, r.inicio_longitud
        )
      end as distancia_usuario_km,
      public.miniatura_de_trazado(r.trazado) as miniatura
    from rutas r
    cross join lateral (
      select public.texto_para_buscar(r.nombre || ' ' || r.autor_nombre)
        as texto
    ) t
    where r.estado = 'publicada'
      and (
        -- Por texto: ninguna palabra puede faltar, y cada una tiene
        -- que ser el comienzo de una palabra. El espacio de adelante
        -- es el que marca dónde empieza cada una.
        (v_con_texto and not exists (
          select 1
          from unnest(v_palabras) as palabra
          where strpos(' ' || t.texto, ' ' || palabra) = 0
        ))
        or (v_con_zona
            and r.inicio_latitud between p_zona_sur and p_zona_norte
            and r.inicio_longitud between p_zona_oeste and p_zona_este)
      )
  ) c
  order by c.distancia_usuario_km asc nulls last,
           c.fecha_publicacion desc,
           c.id
  limit v_limite;
end;
$$;

notify pgrst, 'reload schema';

commit;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. Lo que no es letra ni número separa palabras:
--
--   select public.texto_para_buscar('Vuelta (Laureles-Estadio), 100%');
--
--   Tiene que dar `vuelta laureles estadio 100`.
--
-- 2. Por creador, desde el comienzo del nombre. Cambia "ana" por
--    el comienzo del nombre de quien publicó alguna ruta: salen
--    sus rutas, y no las de alguien cuyo nombre solo lo contiene.
--
--   select nombre, autor_nombre from public.buscar_rutas('ana');
--
-- 3. Mientras se escribe sigue funcionando: con el comienzo de una
--    palabra del nombre de una ruta, sale esa ruta.
--
--   select nombre from public.buscar_rutas('nuti');
--
-- 4. Un pedazo de en medio ya no encuentra nada (salvo que alguna
--    palabra empiece así):
--
--   select count(*) from public.buscar_rutas('tibara');
--
-- 5. Siguen sin poder llamarla quienes no tienen sesión. Las dos
--    columnas tienen que dar `false`:
--
--   select
--     has_function_privilege('anon',
--       'public.buscar_rutas(text,double precision,double precision,double precision,double precision,double precision,double precision,integer)',
--       'execute') as buscar,
--     has_function_privilege('anon', 'public.texto_para_buscar(text)',
--       'execute') as texto;
-- -------------------------------------------------------------
