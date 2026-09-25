# Bugs encontrados y corregidos

Registro de los bugs que aparecen al probar la app y cómo se corrigieron, para tener trazabilidad. Cada entrada dice qué vio el usuario, la evidencia, la causa raíz, el arreglo y cómo se validó. Los intentos fallidos también se documentan: explican por qué la solución final es como es.

| ID | HU | Resumen | Estado |
|----|----|---------|--------|
| [BUG-001](#bug-001-el-ritmo-en-vivo-crece-sin-techo-con-el-usuario-quieto) | SCRUM-116 | El ritmo en vivo crece sin techo con el usuario quieto y tarda en reaccionar al retomar | Corregido |
| [BUG-002](#bug-002-regresión-del-primer-arreglo-mapa-tiempo-y-ritmo-congelados) | SCRUM-116 | Regresión del commit `30d0e10`: mapa, tiempo y ritmo congelados | Corregido (se revirtió) |
| [BUG-003](#bug-003-distancia-inflada-parezco-que-corro-una-maratón) | SCRUM-116 | Distancia y ritmo inflados, "parezco que corro una maratón" | Corregido (misma causa que BUG-001) |
| [BUG-004](#bug-004-el-recorrido-no-se-ve-en-vivo-en-el-mapa) | SCRUM-116 | El recorrido no se dibuja en vivo en el mapa | Corregido |
| [BUG-005](#bug-005-al-reanudar-el-trazo-une-con-una-recta-el-punto-de-pausa-y-el-de-reanudación) | SCRUM-116 | Al reanudar tras moverse en pausa, el trazo une con una recta el punto de pausa y el de reanudación | Corregido en el mapa en vivo; falta el resumen |

Dispositivo de pruebas: tablet Samsung SM-X520 (Android 16). Su GPS entrega fixes con 30-40 m de error (`hAcc=32` en GPS y `~40` por red, según `adb shell dumpsys location`). Casi todos estos bugs salen de ese error: a paso de caminata (~1,4 m/s) es mucho mayor que lo que el usuario avanza entre dos lecturas.

---

## BUG-001: el ritmo en vivo crece sin techo con el usuario quieto

**Reportado:** 2026-09-22 · **HU:** SCRUM-116

**Síntoma**

- Parado, el ritmo sube sin parar (`15'00"`, `40'00"`, `2h/km`...).
- Al volver a caminar, la app tarda varios segundos en reaccionar.
- El marcador del mapa avanza pero los kilómetros no.

**Causa raíz**

1. El ritmo en pantalla era el **promedio de toda la actividad** (`tiempo total / distancia total`). Parado, el tiempo sigue y la distancia no: el número crece sin límite.
2. Se le pedía al sistema `distanceFilter = 5 m` y geolocator usa por defecto una lectura cada **5 s**. Parado no llegaba ninguna lectura, así que la app no tenía forma de saber que el usuario se detuvo ni de enterarse rápido de que arrancó.
3. Dos umbrales de precisión distintos: el stream aceptaba lecturas de hasta 50 m (mueven el marcador) y la calculadora de distancia solo hasta 25 m. Las lecturas intermedias movían el mapa sin sumar distancia.

**Arreglo** (ver también BUG-002 y BUG-003, que salieron de los intentos anteriores)

- **Velocidad Doppler como fuente principal.** Cada lectura trae la velocidad que mide el propio receptor (`Position.speed` y `speedAccuracy`). No depende del error de la posición: sirve con un GPS de 40 m. Se añadieron `velocidadMps` y `precisionVelocidadMps` a `PuntoGps` (no se guardan en `puntos_gps`).
- **Ritmo actual, no promedio.** `VentanaVelocidad` promedia las velocidades de los últimos 10 s:
  - si la última lectura es de reposo, no hay ritmo (`0'00"`) desde ese mismo segundo;
  - al retomar, basta con dos lecturas seguidas en movimiento (una sola puede ser ruido);
  - solo promedia las muestras en movimiento, así que los segundos parados no empeoran el ritmo al retomar.
  El promedio de toda la actividad (`DistanciaEnVivo.ritmoPara`) sigue existiendo para el resumen.
- **Una lectura por segundo, sin filtro del sistema.** `ConfiguracionRastreo`: `distanciaMinimaMetros = 0`, `intervalo = 1 s` (`AndroidSettings.intervalDuration`). El ruido se filtra en la app.
- **Reglas de movimiento compartidas.** `CriterioMovimiento` decide para el trazo y para la distancia:
  - velocidad fiable si `0 < speedAccuracy ≤ 1,5 m/s`;
  - reposo si la velocidad es menor que 0,5 m/s o que su propio error.

**Archivos:** `lib/models/punto_gps.dart`, `lib/models/distancia_en_vivo.dart`, `lib/services/criterio_movimiento.dart` (nuevo), `lib/services/ventana_velocidad.dart` (nuevo), `lib/services/calculadora_distancia.dart`, `lib/services/distancia_provider.dart`, `lib/services/ubicacion_service.dart`, `lib/screens/tracking/tracking_screen.dart`.

**Tests:** `test/services/ventana_velocidad_test.dart` (nuevo), `test/screens/tracking_screen_distancia_test.dart`:

- el ritmo es el del paso actual que mide el GPS;
- parado pasa a `0'00"` al instante sin dispararse;
- al retomar vuelve en dos lecturas.

**Validación en dispositivo (2026-09-24):** parcial.

- Ya no crece sin techo: parado, el ritmo termina en `0'00"`.
- Pero no lo hace al instante. Al detenerse, el ritmo sube de forma escalonada, por ejemplo de `5'10"` a cerca de `9'40"` (el usuario lo anotó como "9"70"), en unos **5 saltos** antes de pasar a `0'00"`. La app sí detecta la parada, pero con varios segundos de retraso.

**Causa probable (sin confirmar):** al frenar, el GPS no reporta 0 de golpe. La velocidad que entrega el proveedor `fused` baja poco a poco (1,4 → 1,0 → 0,7 m/s...), y cada una de esas lecturas sigue por encima del umbral de reposo (0,5 m/s), así que cuenta como movimiento. Además `VentanaVelocidad` promedia 10 s, lo que suaviza todavía más la bajada. El ritmo solo pasa a `0'00"` cuando llega una lectura por debajo de 0,5 m/s o de su propio error.

**Evidencia (2026-09-24, Galaxy A55 SM-A556E conectado por adb).** Se registró en logcat cada lectura que evalúa `distanciaProvider` (`vel`, `sAcc`, `hAcc`, la muestra de velocidad y el ritmo). Con el usuario quieto y luego moviéndose ~3,5 m:

- **Todas** las lecturas llegaban con `vel`, `sAcc` y `hAcc` en `null`, aunque `adb shell dumpsys location` mostraba que Android sí los medía (`hAcc=5.1 vel=0.0 sAcc=0.86`).
- La distancia marcó 10,1 m para ~3,5 m reales, y el ritmo promedio del resumen salió `168'40"` (esos 10,1 m en ~1:42).
- 8 s después de parar apareció un ritmo de `15'39"` que luego volvió a `0'00"` (el usuario lo vio como `13'10"`).

**Causa raíz real**

1. **geolocator_android pierde las banderas `has*`.** `AndroidPosition.fromMap` (4.6.2) llama a `Position.fromMap`, que sí las calcula, pero construye el `AndroidPosition` sin pasarlas: `hasAccuracy`, `hasSpeed` y `hasSpeedAccuracy` quedan siempre en `false`. `UbicacionGeolocator` se fiaba de ellas, así que en Android la precisión y la velocidad llegaban siempre como `null`:
   - la velocidad Doppler **nunca** se usó en el dispositivo: todo se midió por posiciones;
   - con `hAcc = null` la lectura se tomaba como perfecta y el umbral de jitter quedaba en el mínimo (3 m). Eso infla la distancia y la velocidad implícita (probablemente también BUG-003).
2. **Ritmo con muestras caducadas.** Una lectura sin velocidad fiable no deja muestra en `VentanaVelocidad`. Tras parar, las muestras viejas salían de la ventana de 10 s de a una y el ritmo cambiaba a saltos hasta vaciarla: los "5 saltos". Además, la regla de "dos muestras seguidas" solo se aplicaba con 2 o más muestras. Al caducar el reposo quedaba sola una muestra en movimiento de hace segundos y aparecía un ritmo fantasma.
3. **Ancla congelada** (salió al corregir la 1). Las primeras lecturas del GPS llegan sin velocidad y quedaban como ancla. `CalculadoraDistancia` medía el hueco contra el ancla, no contra la lectura anterior, así que todas las lecturas siguientes con velocidad "venían tras un hueco de más de 5 s" y caían al respaldo por posiciones. Resultado: 6 m caminados marcaban 0.

La hipótesis anterior (la velocidad baja poco a poco al frenar) es cierta pero menor: en el A55 pasa de 1,14 a 0,28 m/s en unos 3 s.

**Arreglo**

- `UbicacionGeolocator.aPunto`: un valor distinto de 0 también cuenta como medido (geolocator pone 0 cuando falta). Una velocidad de 0 se cree si viene con su precisión.
- `VentanaVelocidad`: sin ritmo si la última muestra tiene más de 3 s (`vigencia`), y siempre hacen falta dos muestras seguidas en movimiento.
- `CalculadoraDistancia`: integra la velocidad entre la lectura actual y la **anterior**, no contra el ancla. `reiniciarAncla` también olvida la anterior, para no integrar a través de una pausa.

**Tests:** `test/services/ubicacion_service_test.dart` (grupo `aPunto`), `test/services/ventana_velocidad_test.dart` (no sube a saltos, muestra suelta tras caducar el reposo), `test/services/calculadora_distancia_test.dart` (lecturas iniciales sin velocidad, no integra a través de la pausa).

**Validación en dispositivo (2026-09-24, A55):** con el teléfono quieto, `vel`/`sAcc`/`hAcc` ya llegan. Al moverse, el ritmo aparece en la segunda lectura en movimiento y vuelve a `0'00"` un segundo después de parar. Falta validar caminando un tramo de longitud conocida.

**Validación caminando (2026-09-24, A55):** caminata de 6 min a paso medio/lento, con una pausa.

- 0,33 km con ritmo promedio de `18'34"` (~3,2 km/h). Es coherente consigo mismo (0,33 × 18'34" ≈ 6 min) y con un paso lento (3-4 km/h equivale a `15'00"`-`20'00"`).
- El trazo del mapa es mucho más preciso que antes.
- El resumen ya muestra pasos y kcal.

No se midió contra un tramo de longitud conocida: es una validación razonable, no exacta.

**Estado:** corregido.

---

## BUG-002: regresión del primer arreglo: mapa, tiempo y ritmo congelados

**Reportado:** 2026-09-24 · **Introducido en:** commit `30d0e10` ("SCRUM-116: corregir el ritmo y la reacción al salir del reposo")

**Síntoma**

"Ya ni siquiera avanza en el mapa". Tras un rato caminando:

- no se registra el ritmo;
- el marcador no se mueve;
- el cronómetro se detiene;
- después la app se cierra.

**Evidencia**

- `dumpsys location`: el GPS de la tablet entregaba `hAcc=32.14 m` y la red `hAcc=40.6 m`.

**Causa raíz**

1. **Tope de precisión de 30 m.** El commit bajó `ConfiguracionRastreo.precisionMaximaMetros` de 50 a 30 m para unificarlo con la calculadora. La tablet nunca baja de 32 m, así que **todas** las lecturas se descartaban antes de llegar al mapa, al recorrido y a la distancia.
2. **Auto-pausa sin salida.** El commit añadió una auto-pausa: congelaba el cronómetro tras 15 s sin movimiento y solo lo reanudaba con un tramo nuevo aceptado. Si las lecturas dejaban de pasar el filtro, el tiempo quedaba congelado para siempre.

**Arreglo**

- Se revirtió el commit completo (`lib/` y `test/` volvieron a `30d0e10^`).
- La auto-pausa **se eliminó**: el tiempo solo se detiene cuando el usuario pulsa pausa. Si más adelante se quiere, debe ser opcional y con salida garantizada aunque no lleguen lecturas.
- El tope de precisión del stream queda en **50 m**, con un comentario que explica por qué no bajarlo.

**Estado:** corregido.

---

## BUG-003: distancia inflada, "parezco que corro una maratón"

**Reportado:** 2026-09-24 · **HU:** SCRUM-116

**Síntoma**

- Parado, el ritmo "se vuelve loco".
- Al retomar no detecta el movimiento, y cuando lo detecta la distancia y el ritmo no tienen nada que ver con la realidad.
- En palabras del usuario: "parezco que estoy corriendo una maratón".

**Causa raíz**

Con lecturas frecuentes y un error de posición grande, **restar posiciones convierte el jitter en kilómetros**. El umbral de jitter adaptativo del intento anterior (0,5 × precisión, con tope de 15 m) se queda muy corto: dos lecturas de un usuario quieto con 30 m de error pueden estar a 20-40 m una de otra.

**Cómo se midió.** Tests con ruido simulado: una lectura por segundo durante 2 min, con ruido de posición independiente entre lecturas (el peor caso).

| Escenario | Real | Umbral 0,5 × precisión | Umbral 2,5 × precisión |
|-----------|------|------------------------|------------------------|
| Quieto, error 8 m | 0 m | 204 m | 0 m |
| Quieto, error 15 m | 0 m | 413 m | 0 m |
| Caminando 1,4 m/s, error 8 m | 168 m | 257 m | 168-188 m |
| Caminando 1,4 m/s, error 15 m | 168 m | 447 m | 165-175 m |

**Arreglo**

- **La distancia se mide con la velocidad Doppler** (velocidad × tiempo, lectura a lectura). Si el GPS dice que el usuario está quieto, no suma aunque la posición salte, y el ancla se mueve a esa lectura para que el jitter acumulado no se cuente después.
- **`distanciaProvider` evalúa cada lectura del GPS**, no solo los puntos del trazo. Si no viera las lecturas de reposo, al retomar integraría la velocidad sobre todo el rato parado.
- **Tras un hueco de más de 5 s sin lecturas** no se integra velocidad: se mide por posiciones.
- **Respaldo por posiciones** (sin velocidad fiable):
  - umbral de jitter de **2,5 × el error** de la lectura, con tope de 50 m;
  - solo con lecturas de hasta 20 m;
  - límite de 12,5 m/s contra teletransportes.

**Archivos:** `lib/services/calculadora_distancia.dart`, `lib/services/criterio_movimiento.dart`, `lib/services/distancia_provider.dart`.

**Tests:**

- `test/services/calculadora_distancia_test.dart`:
  - grupo "con velocidad Doppler";
  - grupo "simulación con ruido realista del GPS": quieto, caminando, caminar-parar-seguir, sin Doppler.
- `test/services/distancia_provider_test.dart`:
  - evalúa cada lectura;
  - avanza con 40 m de error;
  - quieto con 40 m de error no se inventa distancia.

| Simulación (2 min, error de posición ±20 m) | Real | Resultado |
|---|---|---|
| Quieto con velocidad Doppler | 0 m | < 2 m |
| Caminando | 168 m | 168 m ± 5 % |
| Caminar, parar 1 min, seguir | 168 m | 168 m ± 5 % |

**Validación en dispositivo (2026-09-24):** sin confirmar.

Caminando a unos **5 km/h**, la app marcaba un ritmo de unos **`6'00"`**. Personas que corren dijeron que esa cifra no corresponde al esfuerzo.

Cómo se lee el ritmo: `m'ss"` son **minutos y segundos por kilómetro** (cuánto se tarda en recorrer 1 km). Cuanto más bajo, más rápido.

| Velocidad | Ritmo esperado | Actividad |
|-----------|----------------|-----------|
| 5 km/h (1,39 m/s) | `12'00"` | caminar |
| 6 km/h | `10'00"` | caminar rápido |
| 10 km/h (2,78 m/s) | `6'00"` | trotar |

Es decir, a 5 km/h debería marcar `12'00"`. `6'00"` es ritmo de trote: **la velocidad en que se basa el ritmo sale aproximadamente al doble de la real**. (La velocidad de 5 km/h es una estimación del usuario, no una medición.)

**Causas posibles (sin confirmar):**

- El proveedor `fused` entrega una velocidad calculada a partir de posiciones con 30-40 m de error, en vez de Doppler real, y el jitter la infla. El filtro `sAcc ≤ 1,5 m/s` no lo detectaría si el propio `sAcc` es optimista.
- Cuando no hay velocidad fiable, `CalculadoraDistancia` usa la velocidad implícita entre posiciones (distancia / tiempo) como muestra del ritmo. Con ese error de posición también sale inflada.

No se comprobó si la **distancia** total también salió al doble; conviene comparar con un recorrido de longitud conocida.

**Actualización (2026-09-24):** la causa más probable es la 1 de BUG-001. En Android la velocidad Doppler nunca llegaba a la app, y la precisión tampoco: todo se medía por posiciones, tomando cada lectura como perfecta (umbral de jitter de 3 m con 30-40 m de error real). Eso infla la distancia y la velocidad implícita con la que se calculaba el ritmo.

**Validación (2026-09-24, A55):** caminando a paso medio/lento el ritmo promedio fue `18'34"` (~3,2 km/h), acorde al esfuerzo. Antes marcaba `6'00"` caminando.

**Estado:** corregido.

---

## BUG-004: el recorrido no se ve en vivo en el mapa

**Reportado:** 2026-09-24 · **HU:** SCRUM-116

**Síntoma:** caminando, no se ve la ruta recorrida en el mapa del entrenamiento.

**Causa raíz:** no era una regresión. `MapaRecorrido` solo pintaba el marcador de la posición; el trazo había quedado "para otra HU" y solo se dibujaba en el resumen final.

**Arreglo**

- `MapaRecorrido` dibuja una `PolylineLayer` con los puntos de `recorridoProvider`.
- Con la actividad en curso, el marcador sigue el último punto del recorrido en vez de cada lectura cruda. Así no baila con el ruido del GPS estando quieto, y lo que se ve coincide con los kilómetros.
- En pausa, o antes del primer punto, muestra la lectura cruda.
- El recorrido solo añade un punto si se separa al menos 5 m del anterior y hay movimiento:
  - con velocidad fiable, según esa velocidad;
  - sin ella, si el desplazamiento supera el error de las lecturas.
- Esta regla es más permisiva que la de la distancia: un zigzag en el trazo apenas se nota, pero un marcador que no avanza sí. Los kilómetros no salen del trazo.

**Archivos:** `lib/widgets/mapa_recorrido.dart`, `lib/services/recorrido_provider.dart`.

**Tests:** `test/integration/rastreo_en_vivo_test.dart` comprueba la polilínea con los puntos del recorrido.

**Estado:** corregido.

---

## BUG-005: al reanudar, el trazo une con una recta el punto de pausa y el de reanudación

**Reportado:** 2026-09-24 · **HU:** SCRUM-116

**Síntoma**

1. Pausar el entrenamiento.
2. Moverse a otro lugar con la actividad en pausa.
3. Reanudar.

El mapa dibuja una línea recta desde donde se pausó hasta donde se reanudó, como si ese tramo se hubiera recorrido.

**Comportamiento esperado:** el trazo se corta donde se pausa y vuelve a empezar, como un tramo nuevo, en el punto donde se reanuda. Lo recorrido en pausa no se dibuja.

**Causa raíz**

- `Recorrido` guarda los puntos en **una sola lista**, sin saber dónde hubo pausas. En pausa, `RecorridoNotifier._registrar` ignora las lecturas, pero al reanudar la primera lectura se añade a la misma lista.
- `_esAvance` compara esa lectura con el último punto de antes de la pausa. Como está lejos, pasa el filtro de separación mínima y se acepta.
- `MapaRecorrido` pinta toda la lista con **una única** `Polyline`, así que une los dos puntos con una recta.

La distancia, en cambio, ya corta la continuidad al reanudar (`distanciaProvider` llama a `CalculadoraDistancia.reiniciarAncla()`), así que en principio lo movido en pausa no suma kilómetros. Falta comprobarlo en dispositivo junto con este bug.

**Arreglo**

- `Recorrido` sigue guardando una sola lista de `puntos` (lo que se sincroniza no cambia), más `cortes`: los índices donde empieza un tramo nuevo. `tramos` los separa.
- `RecorridoNotifier`: al pasar de pausa a en curso, la siguiente lectura abre un tramo nuevo y no se compara con el último punto de antes de la pausa.
- `MapaRecorrido` dibuja una `Polyline` por tramo.

**Tests:** `test/models/recorrido_test.dart` (nuevo), `test/services/recorrido_provider_test.dart` (tramo nuevo al reanudar, pausas sin lecturas no dejan tramos vacíos), `test/integration/rastreo_en_vivo_test.dart` (dos polilíneas tras pausar y reanudar).

**Falta:** el mapa del resumen lee los puntos de `puntos_gps`, que no guarda dónde empieza cada tramo, así que ahí la recta sigue. Hace falta una columna nueva (migración en `supabase/migrations/`, aplicada a mano).

**Validación (2026-09-24, A55):** tras pausar, moverse y reanudar, el trazo en vivo queda cortado.

**Estado:** corregido en el mapa en vivo; el resumen queda como deuda (ver `docs/deudas.md`).

---

## Pendiente

- **BUG-001 y BUG-003:** validar la distancia contra un tramo de longitud conocida (por ejemplo, una pista de 400 m).
- **BUG-005:** cortar también el trazo del resumen (ver `docs/deudas.md`).

## Cómo diagnosticar en el dispositivo

```bash
adb logcat -G 16M                                        # buffer grande antes de salir a caminar sin cable
adb logcat -d -s flutter:I                               # logs de la app al volver a conectar
adb shell dumpsys activity exit-info com.traza.traza   # por qué murió el proceso
adb shell dumpsys package com.traza.traza | grep LOCATION   # estado del permiso de ubicación
adb shell dumpsys location                               # últimas lecturas (hAcc, vel, sAcc) y solicitudes de la app
adb logcat -b crash -d                                   # crashes nativos
```
