# Datos de prueba

Con estos datos se recorre el flujo de rutas de TRAZA con los tres roles: corredor, administrador y Runner Experto. Están en la base del proyecto en Supabase, la misma que usa el equipo.

**Las cuentas de prueba no están en este repositorio**, que es público. Los correos y las contraseñas se comparten por el medio privado que indique el docente.

## Cuentas: una por rol

| Rol | Qué hace en el flujo | Cómo se obtiene |
|---|---|---|
| Corredor | Entrena, publica rutas y confirma la publicación de las suyas. | Es el rol básico: toda cuenta nueva lo recibe al registrarse. |
| Administrador | Hace la primera revisión: aprueba la ruta o la rechaza con un motivo. | Lo asigna el equipo en el SQL Editor de Supabase. |
| Runner Experto | Asigna la dificultad, que es su aprobación, o rechaza con un motivo. | En la app se gana con el décimo nivel superado, 150 000 de XP y 6 meses de cuenta (`0012`). Para la cuenta de prueba lo asigna el equipo en el SQL Editor. |

Tienen que ser tres cuentas distintas: nadie aprueba, rechaza ni clasifica su propia ruta.

Para asignar los roles privilegiados, en el SQL Editor (el uid de cada cuenta está en Authentication → Users):

```sql
-- Administrador (0005)
update perfiles set rol = 'admin' where id = 'UID-DE-LA-CUENTA';

-- Runner Experto (0011 y 0012)
insert into roles_usuario (usuario_id, rol) values ('UID-DE-LA-CUENTA', 'experto');
```

## Las seis operaciones: una ruta en cada estado

| Estado | Ruta de prueba | Cómo se llega |
|---|---|---|
| `en_revision` | Vuelta la manzana | El corredor publica un entrenamiento desde su resumen, con "Publicar como ruta". |
| `revision_experto` | Recorrido Medellin | Lo anterior, y el administrador la aprueba en Panel de administrador → "Revisión de rutas". |
| `clasificada` | Arcadia (difícil) y Udem (fácil) | Lo anterior, y el Runner Experto le asigna la dificultad desde "Rutas por clasificar", en su perfil. |
| `publicada` | Rodeo alto y Rodeo alto 2 (moderada), entre 7 publicadas | Lo anterior, y el corredor confirma con "Publicar ruta" en el detalle de su ruta. |
| `rechazada` | Rechazada | El corredor la publica y el administrador la rechaza con un motivo, que es obligatorio. Al corredor le llega el aviso con ese motivo. |
| `datos_incompletos` | Datos incompletos | Se publica un entrenamiento sin distancia: la base la deja así porque no hay con qué clasificarla. Ver abajo cómo se prepara. |

## Cómo reproducirlas desde cero

1. Con el corredor, hacer un entrenamiento **al aire libre, caminando 2 o 3 minutos**. Bajo techo el GPS es impreciso y la app descarta los puntos, y para publicar hacen falta al menos 2.
2. En el resumen del entrenamiento, o desde Historial, tocar "Publicar como ruta". Cada entrenamiento se publica una sola vez, y la ruta empieza en `en_revision`.
3. Para llevarla a cada estado, seguir la tabla de arriba con la cuenta de cada rol.

### Datos incompletos

Un entrenamiento queda sin distancia cuando el GPS registró menos de 5 metros. Pero con tan poco movimiento la app casi nunca guarda los 2 puntos que pide la publicación, así que se prepara a mano:

1. Con el corredor, hacer un entrenamiento corto al aire libre y **no publicarlo todavía**.
2. En el SQL Editor, buscar su id. Esta consulta solo lee:

```sql
select e.id, p.nombre as corredor, e.fecha_fin, e.distancia_total_m,
       (select count(*) from puntos_gps g where g.entrenamiento_id = e.id) as puntos
from entrenamientos e
join perfiles p on p.id = e.usuario_id
where e.estado = 'finalizado'
  and not exists (select 1 from rutas r where r.entrenamiento_id = e.id)
order by e.fecha_fin desc nulls last
limit 5;
```

3. Quitarle la distancia a ese entrenamiento, que debe tener 2 puntos o más. Tiene que devolver 1 fila con la distancia en `NULL`. No toca la XP: el trigger que la otorga solo se dispara cuando cambia el estado del entrenamiento.

```sql
update entrenamientos
set distancia_total_m = null
where id = 'ID-DEL-ENTRENAMIENTO'
  and not exists (select 1 from rutas r where r.entrenamiento_id = entrenamientos.id)
returning id, distancia_total_m;
```

4. Publicarlo desde Historial → el entrenamiento → "Publicar como ruta". La pantalla avisa "Este entrenamiento no registró distancia", y la ruta queda en `datos_incompletos`.

## Comprobar que están todas

Esta consulta solo lee. Muestra cuántas rutas hay en cada estado, y donde falta una dice "— FALTA —":

```sql
with estados(estado, orden) as (
  values ('en_revision', 1), ('revision_experto', 2), ('clasificada', 3),
         ('publicada', 4), ('rechazada', 5), ('datos_incompletos', 6)
)
select e.estado,
       count(r.id) as cuantas,
       coalesce(
         string_agg(r.nombre || ' [' || coalesce(r.dificultad, 'sin dificultad') || ']',
                    ' | ' order by r.fecha_creacion desc),
         '— FALTA —') as rutas
from estados e
left join rutas r on r.estado = e.estado
group by e.estado, e.orden
order by e.orden;
```

## Pendiente y limitaciones

- **Los ocho registros del recurso HTTP** dependen de lo que responda el docente sobre el recurso HTTP del proyecto, que hoy es la búsqueda de zonas con Nominatim.
- **Todavía no hay ninguna revisión de la clasificación (HU-35).** Para probarla, el autor de Arcadia o de Udem confirma su publicación, y la revisa el mismo Runner Experto que la clasificó. Rodeo alto y Rodeo alto 2 no sirven para esto: no tienen registrado quién las clasificó.
- **Algunas rutas publicadas no tienen dificultad**, como Vuelta al mundo. Se publicaron antes de que existiera la clasificación (SCRUM-363).
- **Los datos son de prueba, en la base compartida.** Las rutas publicadas se ven en Explorar para todos los usuarios.
