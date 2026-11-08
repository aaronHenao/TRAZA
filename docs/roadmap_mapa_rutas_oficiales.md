# Roadmap – Mapa de rutas oficiales

El mapa de progresión (`/progreso`, SCRUM-226) deja de ser un camino de niveles. Pasa a ser un camino de **rutas oficiales de TRAZA**: rutas que los corredores publicaron en la app y que el administrador eligió y ordenó. El corredor avanza en el mapa **corriendo cada ruta completa**.

Decidido con Emmanuel:

- **Cómo se avanza:** completando la ruta. La base valida con los puntos GPS del entrenamiento que de verdad se recorrió. El cliente no decide nada.
- **Qué elige el administrador:** qué rutas publicadas son oficiales y su **posición en el camino** (1, 2, 3…). El dibujo sigue siendo el camino de arriba abajo que ya existe.

## Lo que cambia y lo que no

| Qué | Antes | Después |
|---|---|---|
| Paradas del mapa | Niveles, por XP | Rutas oficiales, en el orden del administrador |
| Marcador "Tú" | Último nivel alcanzado | Primera ruta oficial que el corredor no ha completado |
| Niveles y XP | En el mapa y en Tu progresión | Solo en Tu progresión (`/progresion`). La XP sigue saliendo de los retos |
| Tarjeta de nivel de Inicio | Abre el mapa | Abre Tu progresión, que es donde quedan los niveles |
| Rutas publicadas | Se ven en Explorar | Igual. Ser oficial no cambia su estado ni su revisión |
| Panel del administrador | 5 módulos | Uno más: **Mapa de rutas oficiales** |

## Resumen

| Orden | Etapa | Rama | Migración | Tamaño |
|---|---|---|---|---|
| 1 | El administrador elige y ordena las rutas oficiales | `feature/rutas-oficiales-admin` | `0058_rutas_oficiales.sql` | L |
| 2 | El mapa muestra las rutas oficiales | `feature/rutas-oficiales-mapa` | `0059_rutas_completadas.sql` | M |
| 3 | Correr una ruta oficial | `feature/rutas-oficiales-correr` | `0060_entrenar_una_ruta.sql` | M |
| 4 | Validar el recorrido y avanzar en el mapa | `feature/rutas-oficiales-validar` | `0061_verificar_ruta_completada.sql` | L |
| 5 (opcional) | XP por ruta oficial y aviso al autor | `feature/rutas-oficiales-extras` | `0062_...` | S |

Si se crean HU en Jira, la rama y los commits llevan su ID (`feature/SCRUM-X-...`, `SCRUM-X: ...`). Los números de migración se confirman al crear cada una: si otro integrante sube una antes, se corre el número.

**Por qué este orden:** cada etapa termina en algo que se ve corriendo.

1. Sin rutas oficiales no hay nada que mostrar en el mapa.
2. El mapa puede mostrarse antes de poder correr: todas las paradas salen "por recorrer".
3. Correr una ruta no necesita la validación. El entrenamiento queda guardado con su ruta.
4. La validación cierra el ciclo y el marcador avanza.

**Dependencias entre ramas:** cada rama sale de `develop` cuando el PR de la anterior ya esté fusionado. Si todavía no lo está, sale de la rama anterior.

---

## Etapa 1 – El administrador elige y ordena las rutas oficiales

**Criterios de aceptación**

1. En el panel del administrador hay un módulo **Mapa de rutas oficiales** (`/admin/rutas-oficiales`). Solo lo abre el administrador (`SoloAdministrador`).
2. El módulo lista las rutas oficiales en su orden, con posición, nombre, autor, distancia y dificultad. Sin rutas oficiales, muestra un estado vacío que invita a agregar una.
3. **Agregar:** el administrador elige una ruta **publicada** que todavía no sea oficial y queda al final del camino.
4. **Mover:** con subir y bajar cambia la posición. Las demás se reacomodan sin huecos ni posiciones repetidas.
5. **Quitar:** con confirmación, la ruta sale del mapa y las demás se reacomodan. Quienes ya la habían completado conservan ese registro.
6. Un usuario que no es administrador no puede agregar, mover ni quitar, aunque llame a la base directamente.

**Base de datos (`0058_rutas_oficiales.sql`, skill `migracion-segura`)**

- Tabla `rutas_oficiales`:
  - `ruta_id`: clave primaria, referencia a `rutas`, con `on delete cascade`.
  - `posicion`: entero mayor que 0, `unique deferrable initially deferred` para poder intercambiar dos posiciones en una transacción.
  - `agregada_por` y `fecha_agregada`.
- RLS: `select` para autenticados, porque el mapa lo ven todos. **Sin políticas de escritura**, y se revocan `insert`, `update` y `delete` a `anon` y `authenticated`, como en RNF-14 (`0056`).
- Funciones `security definer`, con `set search_path = public` y `es_admin()` adentro:
  - `agregar_ruta_oficial(p_ruta_id)`: exige `estado = 'publicada'` y que no sea oficial; la pone en `max(posicion) + 1`.
  - `mover_ruta_oficial(p_ruta_id, p_posicion)`: renumera en una sola transacción.
  - `quitar_ruta_oficial(p_ruta_id)`: borra la fila y compacta las posiciones.
- Script de verificación con resultados esperados: agregar una ruta no publicada falla, mover deja posiciones `1..n` sin huecos y un corredor recibe `42501`.

**Flutter**

- `lib/models/ruta_oficial.dart`: posición y la `Ruta`.
- `lib/services/rutas_oficiales_service.dart`: `RutasOficialesRepository` con `oficiales()`, `agregar`, `mover` y `quitar`, su implementación `SupabaseRutasOficialesRepository` y su provider. Los errores de Supabase se traducen a excepciones propias.
- `lib/screens/admin/gestion_rutas_oficiales_screen.dart` y un selector de rutas publicadas que no son oficiales. Para listarlas se reusa `RutasRepository.publicadas()` o `buscar()`.
- La tarjeta en `panel_admin_screen.dart` y la ruta en `main.dart`, como las de recompensas.
- Doble de prueba: `test/utiles/rutas_oficiales_repository_falso.dart`.

---

## Etapa 2 – El mapa muestra las rutas oficiales

**Criterios de aceptación**

1. El mapa (`/progreso`) muestra las rutas oficiales en el orden del administrador, con nombre, distancia y dificultad.
2. Cada parada tiene uno de tres estados:
   - **completada**: el corredor ya la corrió;
   - **siguiente**: la primera que le falta en el orden;
   - **bloqueada**: las que vienen después.
3. El marcador "Tú" está en la ruta siguiente. Si las completó todas, está en la última con un mensaje de camino terminado.
4. Una ruta completada fuera de orden se ve marcada, pero no mueve el marcador.
5. Si el administrador reordena, el mapa se recalcula a partir de lo completado. Nadie pierde lo que ya corrió.
6. Tocar una parada abre el detalle de la ruta (`/rutas/:rutaId`).
7. Sin rutas oficiales, el mapa muestra un aviso en lugar del camino.
8. La tarjeta de nivel de Inicio abre Tu progresión (`/progresion`).

**Base de datos (`0059_rutas_completadas.sql`)**

- Tabla `rutas_completadas`:
  - `usuario_id`, `ruta_id`, `entrenamiento_id` y `fecha_completada`;
  - `cobertura`: la fracción del trazado recorrida;
  - clave primaria `(usuario_id, ruta_id)`.
- RLS: `select` solo de lo propio (`auth.uid()`). Sin políticas de escritura y con los mismos `revoke`: solo la llena la función de la etapa 4.
- En esta etapa la tabla queda vacía y todas las paradas salen "siguiente" o "bloqueada".

**Flutter**

- `MapaProgresion` se reescribe para el camino de rutas, conservando su nombre (y el de `ParadaMapa`, `mapaProgresionProvider` y `CaminoProgresion`): sigue siendo el mapa de progresión, ahora medido en rutas, y así no hay que renombrar en todo el código. La regla del marcador ("primera oficial no completada") se calcula ahí, como función pura.
- `CaminoProgresion` se adapta para dibujar paradas de ruta (estado y distancia en lugar de XP), y se reusa el dibujo del camino.
- `mapaProgresionProvider` lee las rutas oficiales y las completadas del usuario. La invalidación que hace hoy `entrenamiento_provider.dart` al cerrar un entrenamiento se conserva.
- `tarjeta_nivel.dart` navega a `ProgresionScreen.ruta`.
- **Pruebas que se reescriben a propósito**, porque el comportamiento cambia: `test/models/mapa_progresion_test.dart`, `test/screens/mapa_progresion_screen_test.dart`, `test/widgets/camino_progresion_test.dart` y la navegación en `test/widgets/tarjeta_nivel_test.dart`. Revisar también `test/services/cierre_entrenamiento_test.dart`.

---

## Etapa 3 – Correr una ruta oficial

**Criterios de aceptación**

1. En el detalle de una ruta oficial que es la **siguiente** del corredor aparece **Correr esta ruta**. En una completada o bloqueada no aparece, y se explica por qué.
2. Al tocarlo se sigue el mismo flujo de iniciar entrenamiento:
   - permiso de ubicación (SCRUM-82);
   - ofrecimiento de salud (SCRUM-131);
   - elegir el tipo de actividad.
   El entrenamiento queda asociado a esa ruta.
3. Durante el entrenamiento, el mapa del tracking muestra el trazado de la ruta como guía, además del recorrido en vivo.
4. El resumen dice qué ruta se corrió.

**Base de datos (`0060_entrenar_una_ruta.sql`)**

- `entrenamientos.ruta_id uuid null references rutas(id) on delete set null`. Lo escribe el cliente al crear el entrenamiento.
- La policy de `insert` de `entrenamientos` se rehace: con `ruta_id`, solo una ruta que hoy es oficial.
- Un trigger impide cambiar `ruta_id` después de crear el entrenamiento (salvo volver a null, que es lo que hace el `on delete set null`). Sin él, la policy de `update` dejaría reetiquetar un recorrido viejo, o uno largo varias veces, para completar rutas sin correrlas.
- No da ventaja por sí sola: la validación de la etapa 4 no le cree al cliente que la completó, mira los puntos.

**Flutter**

- `EntrenamientoService` acepta la ruta al iniciar.
- `ActividadScreen` y el tracking reciben la ruta elegida, igual que hoy reciben la actividad elegida (SCRUM-93).
- La guía va como una capa más en `lib/widgets/mapa_trayecto.dart` o `mapa_recorrido.dart`, la que use el tracking.

---

## Etapa 4 – Validar el recorrido y avanzar en el mapa

**Criterios de aceptación**

1. Al finalizar un entrenamiento asociado a una ruta oficial, la base decide si se completó. La ruta cuenta como completada si al menos el **90 %** de los puntos del trazado tiene algún punto GPS del entrenamiento a **40 m** o menos.
2. Si se completó, queda en `rutas_completadas` y el mapa avanza.
3. Si no, el resumen dice cuánto se cubrió (por ejemplo, "Cubriste el 72 % de la ruta") y la ruta sigue como siguiente.
4. Completarla de nuevo no duplica nada.
5. Si los puntos se subieron después, por falta de red, la verificación se repite cuando terminan de subir.
6. Nadie puede marcar una ruta como completada sin los puntos que la cubran, ni hacerlo sobre el entrenamiento de otro.

**Base de datos (`0061_verificar_ruta_completada.sql`)**

- `verificar_ruta_completada(p_entrenamiento_id) returns numeric`, que devuelve la cobertura. Es `security definer`, con `set search_path = public`, `revoke execute ... from public, anon`, y estas reglas:
  - el entrenamiento es de `auth.uid()` (sin parámetro de usuario), está `finalizado` y tiene `ruta_id`. Si es de otro o no existe, el mismo `42501`;
  - la ruta es oficial, comprobado antes de leer el trazado;
  - **horas del servidor, no del teléfono**: un trigger fija `fecha_inicio := now()` al crear y no deja cambiarla, y otra marca del servidor al pasar a `finalizado`. Se exige `fecha_inicio >= rutas_oficiales.fecha_agregada` (nada retroactivo) y una duración real de al menos `distancia_km` / una velocidad máxima plausible;
  - solo cuentan los puntos con `capturado_en` dentro de esa ventana, y se descartan los saltos entre puntos consecutivos (por `orden_secuencia`) con velocidad imposible;
  - tope de puntos evaluados por entrenamiento y `set statement_timeout` en la función: si no, alguien podría insertar un millón de puntos y llamarla en bucle contra la base compartida;
  - compara `rutas.trazado` (jsonb) con `puntos_gps` usando `distancia_km_entre` (`0037`), con un filtro previo por caja de ±0.0005° (unos 55 m) para no comparar todos los puntos contra todos;
  - si la cobertura llega al umbral, `insert ... on conflict do nothing`.
- Las tolerancias (40 m y 90 %) van como constantes con nombre al inicio de la función, para ajustarlas en una migración nueva si el equipo lo decide.
- Script de verificación con datos sintéticos:
  - una ruta de 10 puntos y un recorrido que pasa por los 10 → 1.0 y queda registrada;
  - uno que pasa por 7 → 0.7 y no queda;
  - el entrenamiento de otro → `42501`.
  - Medir también el tiempo con un entrenamiento real de 1 hora.

**Flutter**

- `EntrenamientoService` llama a la función al cerrar y `ResumenScreen` muestra el resultado.
- `ReenvioRecorridos` (SCRUM-292) la vuelve a llamar cuando sube lo que había quedado pendiente.
- Se invalida el provider del mapa.

---

## Etapa 5 (opcional) – XP y aviso al autor

- **XP por completar una ruta oficial:** hoy la XP sale solo de los retos (SCRUM-192). Si se quiere, se otorga desde `verificar_ruta_completada` con una regla nueva de `regla_experiencia`. Nunca desde el cliente.
- **Aviso al autor** ("Tu ruta ahora es oficial"): un tipo nuevo de notificación, que se crea en `agregar_ruta_oficial`.

---

## Decisiones abiertas (con propuesta)

| Decisión | Propuesta | Alternativa |
|---|---|---|
| ¿Se puede correr una ruta bloqueada? | No desde la app: solo la siguiente. La base acepta cualquier oficial, así un reordenamiento no invalida lo hecho | Orden libre |
| Tolerancias | 40 m y 90 % | Más estrictas si se ven trampas, más laxas si el GPS falla mucho |
| ¿Importa el sentido del recorrido? | No: solo la cobertura | Exigir que empiece cerca del inicio |
| Rutas publicadas con los 200 m recortados (RNF-04) | Se valida contra el trazado publicado, así que correr la ruta real lo cubre igual | — |
| ¿Completar da XP? | No en esta versión (etapa 5) | Sí, desde la base |
| Quitar una ruta oficial | Sus completadas se conservan; el camino se recalcula | Ocultarla con una marca de inactiva |

## Riesgos y límites

- **Puntos fabricados:** la base valida los puntos, pero los puntos los manda el teléfono. No hace falta una app de ubicación falsa: con la publishable key y su propia sesión, un script puede leer el trazado de una ruta publicada e insertar esos mismos puntos. Las reglas de horas y velocidad de la etapa 4 lo encarecen (hay que fingir el tiempo real de la carrera), pero no lo impiden. Pasa lo mismo con la distancia de los retos; va a *Límites conocidos*, y pesa más si la etapa 5 da XP.
- **Rendimiento de la validación:** un entrenamiento largo puede tener miles de puntos. El filtro por caja y el trazado simplificado (`simplificador_trazado.dart`) lo mantienen acotado. Medirlo en la etapa 4 antes del PR.
- **Puntos sin subir:** si la validación corre antes de que lleguen todos los puntos, da una cobertura baja. Por eso se repite tras el reenvío (criterio 5 de la etapa 4).
- **Cambio de comportamiento del mapa:** las pruebas del mapa de niveles se reescriben (etapa 2). Avisar al equipo, porque SCRUM-226 era de otro integrante.
- **Migraciones compartidas:** son 4 migraciones sobre la base de los cuatro. Cada una se avisa en el grupo antes de correrla y sube en el mismo PR que la usa.

## Flujo de cada etapa

1. **Preparar.** Claude crea la rama desde `develop` actualizado.
2. **Rojo.** El agente `escritor-tests` traduce los criterios en pruebas. Se confirma que fallan por la razón correcta.
3. **Migración.** Se escribe con la skill `migracion-segura`, con su script de verificación y los resultados esperados. Emmanuel avisa en el grupo y la aplica una vez en el SQL Editor.
4. **Verde.** Implementación mínima.
5. **Refactor.** `dart format` solo sobre los archivos propios. Luego `flutter analyze` sin issues y `flutter test` en verde.
6. **Auditar.** Se corre la skill `auditar` y se corrige lo bloqueante.
7. **Cerrar.** Lo que dependa de otra etapa va a `docs/deudas.md`, incluida la nota de SCRUM-226 sobre "Unificar con Tu progresión". Claude entrega los comandos de commit, el `push` y el enlace del PR a `develop`.
