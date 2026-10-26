-- =============================================================
-- TRAZA — Sprint 3 · SCRUM-253 (HU-30): buscar rutas por texto
--
-- La consulta que responde "¿dónde está esa ruta?": recibe lo que
-- el usuario escribió y devuelve las rutas publicadas cuyo nombre
-- o creador coinciden con ello, y las que arrancan dentro de una
-- zona, estén donde estén. Si se sabe dónde está el usuario,
-- salen de la más cercana a la más lejana, como en Explorar
-- rutas.
--
-- Decisiones:
--
--   · Una función aparte, no `rutas_cercanas` con un parámetro
--     más. La búsqueda existe para encontrar rutas que NO están
--     cerca —lo dice HU-30—, así que no puede llevar el radio de
--     50 km. Y cambiar la firma de `rutas_cercanas` obligaría a
--     borrarla y crearla otra vez mientras la app la usa.
--     Devuelve las mismas columnas que ella, para que el cliente
--     lea las dos igual.
--
--   · La zona se busca por geografía, no por texto. Una ruta solo
--     guarda dónde arranca (`inicio_latitud/inicio_longitud`,
--     0029): no hay municipio ni barrio que comparar. Quien llama
--     manda la caja de la zona —sus cuatro bordes— y vuelven las
--     rutas que arrancan dentro. Pasar de "Envigado" a esa caja le
--     toca a la app, en otra subtarea. Así sirve también para las
--     rutas que ya existen, sin tocar cómo se publican.
--
--   · Sin tildes ni mayúsculas: "ciclovia" encuentra "Ciclovía
--     del río", y "ANA", a Ana. Lo hace `texto_para_buscar` con
--     `translate`, sin la extensión `unaccent`: no hay que
--     habilitar nada, no depende del idioma de la base y la
--     función queda `immutable`, que es lo que pediría un índice
--     si algún día hace falta.
--
--   · Palabra por palabra: cada palabra de lo escrito tiene que
--     aparecer en el nombre o en el creador, en cualquier orden.
--     "norte parque" encuentra "Vuelta al Parque Norte", y
--     "nutibara ana", las rutas de Ana por el Nutibara.
--
--   · Con `strpos`, no con `like`: lo escrito se busca tal cual.
--     Un `%` o un `_` no son comodines que devuelvan todo.
--
--   · Al menos dos letras: con una sola coincide casi todo. Sin
--     eso y sin zona no hay búsqueda, y se rechaza con 22023: la
--     app no debería llamarla así.
--
--   · El creador es `autor_nombre`, la copia que guarda la ruta
--     (0029): `perfiles` solo deja leer el perfil propio. Es
--     además el nombre que el usuario ve en la tarjeta.
--
--   · `security invoker`, como 0037: respeta RLS, y el filtro por
--     estado va además escrito en la consulta.
--
--   · El permiso de ejecutarla se le quita también a `anon`, no
--     solo a `public`: Supabase le da a `anon` permiso explícito
--     sobre cada función nueva del esquema `public`, y quitárselo
--     a `public` no lo toca. Por eso 0037 y 0038, que solo se lo
--     quitaron a `public`, dejaron `rutas_cercanas` y sus
--     auxiliares al alcance de quien no tiene sesión: devolvían
--     vacío, porque RLS no le deja ver ninguna ruta, pero la
--     intención era que ni entrara. Aquí se cierra también eso.
--
--   · Es 0040 y no 0039: la rama de recompensas (SCRUM-385) ya
--     usa 0039.
--
-- Lo que NO hace esta migración:
--
--   · No convierte el nombre de una zona en coordenadas: eso es
--     de la app.
--   · No busca en la descripción: HU-30 pide nombre, zona y
--     creador.
--   · No filtra por dificultad ni por distancia: HU-36 y HU-37 se
--     montan encima.
--   · No usa índice para el texto: con las rutas que hay, recorrer
--     las publicadas es inmediato. Si algún día son decenas de
--     miles, un índice de trigramas sobre `texto_para_buscar(
--     nombre || ' ' || autor_nombre)` lo resuelve sin cambiar la
--     función.
--
-- Corre esto DESPUÉS de 0038_miniatura_de_ruta.sql (de ahí salen
-- `distancia_km_entre` y `miniatura_de_trazado`).
-- =============================================================

begin;

-- -------------------------------------------------------------
-- Un texto como se compara al buscar
--
-- Sin tildes, en minúsculas, sin espacios al principio ni al
-- final y con los de en medio reducidos a uno. La ñ pasa a n:
-- quien busca "pena" también quiere "Peña", y en un teclado sin
-- ñ no hay otra forma de escribirla.
--
-- Primero `translate` y después `lower`, y con las mayúsculas
-- acentuadas en la lista: así no depende de que el idioma de la
-- base sepa pasar "Á" a "á".
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
    '\s+', ' ', 'g'
  ));
$$;

comment on function public.texto_para_buscar(text) is
  'Un texto sin tildes, en minúsculas y con los espacios normalizados, para comparar al buscar (SCRUM-253).';

-- -------------------------------------------------------------
-- Las rutas publicadas que coinciden con una búsqueda
--
-- `p_termino`: lo que escribió el usuario. Coincide con el
-- nombre y el creador.
-- `p_zona_*`: los bordes de una zona, los cuatro o ninguno.
-- Coinciden las rutas que arrancan dentro.
-- `p_latitud/p_longitud`: dónde está el usuario, si se sabe.
-- Solo ordena: no recorta nada.
--
-- Una ruta vuelve si coincide por texto O por zona: quien busca
-- "Envigado" quiere las que se llaman así y las que están allá.
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

  -- Calificado con alias por lo mismo que en 0037: los nombres de
  -- lo que devuelve la función también son variables aquí dentro.
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
    -- Donde se busca el texto: el nombre y el creador, juntos, como
    -- se compara.
    cross join lateral (
      select public.texto_para_buscar(r.nombre || ' ' || r.autor_nombre)
        as texto
    ) t
    where r.estado = 'publicada'
      and (
        -- Por texto: ninguna palabra puede faltar.
        (v_con_texto and not exists (
          select 1
          from unnest(v_palabras) as palabra
          where strpos(t.texto, palabra) = 0
        ))
        -- Por zona: arranca dentro de la caja.
        or (v_con_zona
            and r.inicio_latitud between p_zona_sur and p_zona_norte
            and r.inicio_longitud between p_zona_oeste and p_zona_este)
      )
  ) c
  -- Con la ubicación, de la más cercana a la más lejana; sin ella
  -- la distancia es nula en todas y manda la fecha, como en la
  -- lista sin ubicación. El id al final deja el orden fijo entre
  -- consultas aunque dos rutas se publiquen en el mismo instante.
  order by c.distancia_usuario_km asc nulls last,
           c.fecha_publicacion desc,
           c.id
  limit v_limite;
end;
$$;

comment on function public.buscar_rutas(
  text,
  double precision, double precision,
  double precision, double precision, double precision, double precision,
  integer
) is 'Rutas publicadas cuyo nombre o creador coinciden con un texto, o que arrancan en una zona (SCRUM-253). Respeta RLS: solo devuelve lo publicado.';

-- -------------------------------------------------------------
-- Quién puede llamarlas
--
-- Solo quien tiene sesión, como `rutas_cercanas`.
-- -------------------------------------------------------------
revoke all on function public.texto_para_buscar(text) from public, anon;
revoke all on function public.buscar_rutas(
  text,
  double precision, double precision,
  double precision, double precision, double precision, double precision,
  integer
) from public, anon;

grant execute on function public.texto_para_buscar(text) to authenticated;
grant execute on function public.buscar_rutas(
  text,
  double precision, double precision,
  double precision, double precision, double precision, double precision,
  integer
) to authenticated;

-- Lo que 0037 y 0038 quisieron cerrar y no cerraron. Quien tiene
-- sesión conserva su permiso: el que le dieron ellas.
revoke execute on function public.distancia_km_entre(
  double precision, double precision, double precision, double precision
) from anon;
revoke execute on function public.miniatura_de_trazado(jsonb, integer)
  from anon;
revoke execute on function public.miniatura(public.rutas) from anon;
revoke execute on function public.rutas_cercanas(
  double precision, double precision, double precision, integer
) from anon;

-- Para que PostgREST vea la función nueva sin esperar a notarlo
-- solo.
notify pgrst, 'reload schema';

commit;

-- -------------------------------------------------------------
-- Comprobación (correr después, en el SQL Editor)
--
-- 1. El texto se normaliza:
--
--   select public.texto_para_buscar('  Ciclovía   del RÍO  ');
--
--   Tiene que dar `ciclovia del rio`.
--
-- 2. Sin tildes ni mayúsculas, por nombre. Cambia "nutibara" por
--    una palabra del nombre de alguna ruta publicada:
--
--   select nombre, autor_nombre
--   from public.buscar_rutas('NUTIBARA');
--
-- 3. Por creador. Cambia "ana" por el nombre de quien publicó
--    alguna ruta:
--
--   select nombre, autor_nombre from public.buscar_rutas('ana');
--
-- 4. Las palabras en cualquier orden. Con dos palabras del nombre
--    de una ruta, al revés, tiene que salir esa ruta:
--
--   select nombre from public.buscar_rutas('norte parque');
--
-- 5. `%` y `_` no son comodines: esto no puede devolver nada
--    (salvo que una ruta tenga "__" en el nombre):
--
--   select count(*) from public.buscar_rutas('__');
--
-- 6. Por zona, aunque esté lejos. Con la caja del centro de
--    Medellín salen las que arrancan ahí; con la de Bogotá, nada:
--
--   select nombre from public.buscar_rutas(
--     null,
--     p_zona_sur => 6.20, p_zona_oeste => -75.62,
--     p_zona_norte => 6.30, p_zona_este => -75.54
--   );
--   select count(*) from public.buscar_rutas(
--     null,
--     p_zona_sur => 4.55, p_zona_oeste => -74.20,
--     p_zona_norte => 4.75, p_zona_este => -74.00
--   );
--
-- 7. Con la ubicación, de la más cercana a la más lejana:
--
--   select nombre, round(distancia_usuario_km::numeric, 2) as km
--   from public.buscar_rutas(
--     null, p_latitud => 6.2442, p_longitud => -75.5812,
--     p_zona_sur => 6.20, p_zona_oeste => -75.62,
--     p_zona_norte => 6.30, p_zona_este => -75.54
--   );
--
--   Cada fila tiene que tener un km mayor o igual que la anterior.
--
-- 8. Sin qué buscar, o con una zona a medias, se rechaza con
--    22023:
--
--   select * from public.buscar_rutas('a');
--   select * from public.buscar_rutas('parque', p_zona_sur => 6.2);
--
-- 9. Sin sesión no se puede llamar ninguna de las consultas de
--    rutas. Las cuatro columnas tienen que dar `false`:
--
--   select
--     has_function_privilege('anon',
--       'public.buscar_rutas(text,double precision,double precision,double precision,double precision,double precision,double precision,integer)',
--       'execute') as buscar,
--     has_function_privilege('anon',
--       'public.rutas_cercanas(double precision,double precision,double precision,integer)',
--       'execute') as cercanas,
--     has_function_privilege('anon', 'public.miniatura(public.rutas)',
--       'execute') as miniatura,
--     has_function_privilege('anon',
--       'public.distancia_km_entre(double precision,double precision,double precision,double precision)',
--       'execute') as distancia;
--
-- 10. No se salta RLS. Desde el SQL Editor se corre como
--     propietario y RLS no aplica, así que esto se prueba desde
--     la app: una ruta en revisión no aparece ni para su autor.
-- -------------------------------------------------------------
