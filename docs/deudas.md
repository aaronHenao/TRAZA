# Deudas pendientes

Trabajo que quedó hecho en código pero no se puede terminar o probar del todo porque depende de algo que todavía no existe. Cuando se resuelva, se borra de aquí.

## SCRUM-131 / SCRUM-79: datos de salud en retos, rutas y entrenamientos

**Qué quedó hecho (SCRUM-37 y SCRUM-131):**

- `SaludHealth` (`lib/services/salud_service.dart`) lee de Health Connect o Apple Health la frecuencia cardiaca promedio y máxima, las calorías activas y los pasos entre dos horas.
- `SeccionSalud` (`lib/widgets/seccion_salud.dart`) los muestra. Sin permiso, si el usuario eligió entrenar sin datos de salud o si no se registró nada, no aparece.
- Criterio 1: la tarjeta de salud de Permisos (onboarding) explica para qué se usan y tiene el botón "Aceptar".
- Criterio 3: `ofrecerPermisoSalud` (`lib/widgets/ventana_permiso_salud.dart`) muestra la ventana cada vez que se va a iniciar y falta el permiso. Va antes de crear el entrenamiento, así que cerrarla no deja nada a medias.
- Entrenamiento libre: la ventana sale al tocar "Iniciar actividad" y los datos se ven en el Resumen, debajo del ritmo.

**Qué falta:**

- **Retos y rutas no existen todavía.** Cuando se hagan:
  - antes de arrancar, igual que el entrenamiento libre (`ActividadScreen._iniciar`):
    ```dart
    if (!await ofrecerPermisoSalud(context, ref)) return;
    ```
  - en su resumen:
    ```dart
    SeccionSalud(ventana: (inicio: horaDeInicio, fin: horaDeFin))
    ```
- **Health Connect bloqueado.** Si el usuario lo negó dos veces, Health Connect ya no muestra su ventana: "Aceptar" no abre nada y se entrena sin datos. La tarjeta de Permisos no distingue ese caso. Habría que llevarlo a los ajustes de Health Connect.
- **Diseño.** El prototipo no tiene lugar para estas métricas; se usó el mismo estilo de caja que Tiempo y Distancia. Validarlo con el equipo.
- **Probar con datos reales.** El emulador no tiene reloj ni datos de salud. Hace falta un celular con Health Connect y un reloj o Google Fit, o una app que inserte datos de prueba.
- **Inicio del entrenamiento aproximado.** Se toma la hora del primer punto GPS; sin puntos, la hora de fin menos la duración, que no cuenta las pausas. Si `entrenamientos` llega a guardar la hora real de inicio, conviene usarla.
- **iOS.** Falta activar la capacidad HealthKit en Xcode (requiere Mac).

## SCRUM-131 / SCRUM-84: datos de salud en la foto para compartir

**Qué quedó hecho (SCRUM-37):**

- `SaludCompartible` (`lib/widgets/salud_compartible.dart`): los datos de salud en texto blanco con sombra, listos para ir encima de la foto. Sigue la misma regla que el resumen: sin permiso, la foto sale sin ellos.

**Qué falta:**

- **La foto compartible no existe.** No hay HU, pantalla, diseño ni paquete para generar la imagen y compartirla. Quien la haga pone el widget encima:
  ```dart
  Stack(children: [
    foto,
    Positioned(left: 16, bottom: 16, child: SaludCompartible(ventana: ventana)),
  ])
  ```
- En Jira: enlazar la SCRUM-84 como bloqueada por la HU de la foto cuando exista.

## SCRUM-193: insignias por XP

**Qué quedó hecho:**

- `0010_insignias.sql`: catálogo de 9 insignias, `insignias_usuario` y el trigger `otorgar_insignias`, que las otorga al entrar XP (criterios 1 a 5). Al final trae un script de verificación para el SQL Editor.
- `SeccionInsignias` (`lib/widgets/seccion_insignias.dart`) las muestra en Perfil (fuera del onboarding) y en Tu progresión (criterio 6).

**Qué falta:**

- **Aplicar la 0010 y correr su script de verificación.** Antes de aplicarla, revisar que en `experiencia_ganada` no haya XP inflada (retos con XP desproporcionada, días con más de 125 XP de actividad): el backfill le daría insignias a esa XP, y las insignias se conservan aunque después se limpie.
- **Anunciar la insignia nueva en el resumen del entrenamiento.** Quedó fuera: la HU pide verlas al consultar la información, no al terminar. Se haría como el ascenso de nivel (SCRUM-197), con `xp_al_obtener` o la fecha de obtención.
- **Componentes repetidos.** `_Rotulo` y `_Pastilla` de `SeccionInsignias` repiten los de `progresion_screen.dart`, `gestion_niveles_screen.dart` y `gestion_retos_screen.dart`. Falta un `Pastilla` y un `Rotulo` compartidos en `lib/widgets/`. De paso, renombrar `_Insignia` de `progresion_screen.dart` (es la pastilla "N XP" del siguiente nivel, no una insignia).
- **Si la progresión no carga, las insignias tampoco se ven**: la sección vive dentro de las ramas de datos de `ProgresionScreen`. Sacarla del `switch` implica reestructurar la pantalla.

## SCRUM-226: mapa de progresión

**Qué quedó hecho:** pestaña **Progreso** en la barra inferior (`MapaProgresionScreen`, ruta `/progreso`) con el camino de niveles y el marcador "Tú". Sin niveles, muestra solo el punto inicial y un aviso.

**Qué falta:**

- **Unificar con Tu progresión.** El equipo decidió dejar el mapa como pantalla aparte por ahora. Hoy conviven `/progreso` (mapa, en la barra) y `/progresion` (Tu progresión, desde Inicio), con nombres muy parecidos. Si se unen, la sección de insignias y la barra de avance de `ProgresionScreen` pasarían debajo del mapa.
- **Diseño.** El prototipo no tiene pantalla de mapa; se usó el estilo de las tarjetas existentes. Validarlo con el equipo.

## SCRUM-192: la XP sale solo de los retos

**Qué quedó hecho:** `0018_xp_solo_por_retos.sql`, aplicada en Supabase el 2026-10-06. El entrenamiento libre ya no da XP: sus km solo avanzan los retos activos del mismo tipo de actividad, y completar un reto es la única forma de ganar XP. La XP de actividad ya ganada se conservó.

**Qué falta:**

- **Recalibrar las insignias (SCRUM-193).** Los umbrales y textos de `0010_insignias.sql` se pensaron a 5 XP por km ("Primera huella: tu primer kilómetro", 5 XP). Ahora solo se llega con retos: el primer reto completado ya da varias de golpe y los textos de km dejan de ser ciertos. Cambiarlos es otra migración (`update insignias`), y las ya otorgadas se conservan.
- **Revisar los 150 000 XP del rol de Runner Experto (SCRUM-227).** Están en `0012_rol_experto.sql` y en `RequisitosRunnerExperto.experiencia`. Solo con retos, el número depende de la `xp_otorgada` que pongan los admins: con retos de 100 a 500 XP harían falta cientos de retos.
- **Guía para el admin al crear retos.** La de SCRUM-192 ("un reto paga de 3 a 5 veces lo que dan sus km") ya no aplica. Hace falta una nueva, pensada junto con los umbrales de niveles e insignias.

## SCRUM-323 / SCRUM-347: moderación de la IA antes de difundir una publicación

**Qué quedó hecho (SCRUM-323):**

- `publicaciones_foro` (`0020_foro_publicaciones.sql`) tiene `estado` (`publicada`, `retenida`, `eliminada`) y `motivo_moderacion`. La policy de select solo deja ver lo `publicada`; lo retenido lo ven su autor y el administrador.
- El trigger `publicaciones_foro_preparar` hace nacer toda publicación `publicada`: el cliente no puede elegir el estado.
- La app ya contempla el estado retenido: `CreacionPublicacion` devuelve `PublicacionRetenida` si la base responde `retenida`, y el formulario avisa "Tu publicación quedó retenida para revisión" (criterio 3). La moderación del administrador (`/admin/foro`) tiene la pestaña "Retenidas" con el motivo.

**Qué falta:**

- **La IA no existe todavía** (criterio 3 de SCRUM-323, subtarea SCRUM-347; se sigue en SCRUM-322). Hay que decidir dónde corre (Edge Function de Supabase, o una función llamada desde el trigger) y que sea ella quien deje la fila en `retenida` con su `motivo_moderacion` **antes** de devolverla al insertar. Para que la app se entere sin más cambios, el estado tiene que venir ya puesto en la fila que devuelve el `insert ... select`.
- **El administrador todavía no modera.** Ya publica, comenta y edita lo suyo (SCRUM-354, SCRUM-355), pero aprobar una retenida o eliminar una publicación ajena llega con SCRUM-322 y SCRUM-242. Ojo: el trigger `publicaciones_foro_proteger` (`0024_foro_editar_publicacion.sql`, su función la reemplaza `0025_foro_historial_de_versiones.sql`) no deja cambiar `estado` ni `motivo_moderacion` en ningún update; la moderación tendrá que abrirle paso al administrador ahí, además de su policy.

## SCRUM-324: el autor no puede eliminar su propia publicación

**Qué quedó hecho (SCRUM-355):**

- El autor edita el título y el contenido de lo suyo mientras esté publicado, con confirmación antes de guardar. Policy de update y trigger `publicaciones_foro_proteger` en `0024_foro_editar_publicacion.sql`.

**Qué falta:**

- **Eliminar la propia publicación.** No hay botón ni policy de delete en `publicaciones_foro`. Decidir antes de hacerlo:
  - si se borra la fila (los comentarios caen con ella por el `on delete cascade` de `comentarios_foro`) o se marca `estado = 'eliminada'`, que ya existe y oculta la publicación sin perder el rastro para la moderación. Lo segundo choca con el trigger de 0024 y 0025, que no deja cambiar el estado. Si se borra la fila, el historial de versiones también se va (`on delete cascade`).
  - la confirmación: es destructiva de verdad, así que el diálogo debe decir que también se van los comentarios.
- Cuando se haga, el botón va junto al de editar en `DetallePublicacionScreen` y se ofrece con la misma regla (`PublicacionForo.editablePor`).

## SCRUM-357: foro en tiempo real con Postgres Changes

**Qué quedó hecho:**

- `0028_foro_tiempo_real.sql` publica `publicaciones_foro` y `comentarios_foro` en Supabase Realtime.
- `SupabaseCambiosForo` (`lib/services/cambios_foro.dart`) escucha con Postgres Changes. `foroEnVivoProvider` y `publicacionEnVivoProvider` no pintan lo que llega: esperan 500 ms y recargan las consultas de siempre, que pasan por RLS.
- El foro avisa "N publicaciones nuevas · Ver" en vez de mover la lista. La conexión solo existe mientras hay una pantalla del foro abierta.

**Qué falta:**

- **Probarlo contra Supabase de verdad.** `SupabaseCambiosForo` no tiene pruebas automáticas: necesita el WebSocket real. Validar con dos dispositivos y revisar en Realtime → Reports que las conexiones se cierran al salir del foro.
- **Pasar a Broadcast desde la base cuando haya moderación o más usuarios.** Postgres Changes hace una lectura de RLS por cada suscriptor en cada cambio y no avisa a quien deja de ver una fila: si una publicación pasa a `retenida`, quien la tiene abierta no recibe el evento (se entera en su siguiente acción). Con `realtime.broadcast_changes` en un trigger y un canal privado, un cambio es un solo mensaje y se puede avisar también lo que se retira. La app no cambia: solo `SupabaseCambiosForo`.

## SCRUM-322: moderación del foro con IA (Nemotron 3.5 Content Safety)

**Qué quedó hecho:**

- `0035_foro_moderacion_ia.sql`: lo que escribe un corredor (publicación, comentario o edición) queda `en_revision` y se anota en `moderaciones_foro`, que es a la vez la cola, el historial de auditoría y las faltas de cada usuario. Un trigger avisa a la Edge Function con pg_net. Las ediciones van por `editar_publicacion_foro` / `editar_comentario_foro` y no tocan lo publicado hasta que se aprueban. El administrador decide con `decidir_moderacion`. Lo del administrador no pasa por la IA.
- Edge Function `supabase/functions/moderar-foro/`: doble pasada con Nemotron (taxonomía estándar + política de TRAZA en `politica_traza.ts`) y señales de spam sin IA. Si coinciden rechaza, si no coinciden deja pendiente para el administrador, y si NVIDIA falla también deja pendiente. Pruebas: `node --test` (o `deno test`) dentro de la carpeta; CI no las corre.
- App: "En revisión" para el autor, pestañas de moderación con responsable, fecha exacta y motivo, "Mis rechazados" con faltas, contador en el foro y aviso en vivo del rechazo.

- Activa en el proyecto compartido desde el 2026-10-17: 0035 aplicada (se aplicó cuando todavía se llamaba 0029, antes de traer las rutas de develop), secreto en Vault, función desplegada y secretos `NVIDIA_API_KEY` y `MODERACION_WEBHOOK_SECRET` guardados. Una vez listo todo, se vio que "Odio a los peruanos" sale rechazada como discurso de odio en menos de 5 s.

**Cómo se opera:**

- Desplegar tras cambiar la función: `npx supabase@2 functions deploy moderar-foro --project-ref prrumhnwizdirntqvynk --no-verify-jwt --use-api` (requiere `npx supabase@2 login` en una terminal propia; el `!` de Claude Code no es interactivo).
- Cambiar un secreto (rol Admin u Owner en la organización): `npx supabase@2 secrets set NVIDIA_API_KEY=... --project-ref prrumhnwizdirntqvynk`.
- Si algo se queda en revisión: Dashboard → Edge Functions → `moderar-foro` → Logs, y en el SQL Editor `select status_code, content, error_msg, created from net._http_response order by created desc limit 10;`. Si `vault.decrypted_secrets` no tiene `moderacion_webhook_secret`, el trigger no avisa a nadie.
- No usar `supabase db push`: intentaría aplicar todas las migraciones sobre la base compartida.

**Qué falta:**

- **Rotar la key de NVIDIA**: la primera se compartió en un chat. Generar otra en build.nvidia.com, guardarla con `secrets set` y revocar la anterior.
- **Reintentos del aviso**: pg_net manda el aviso una sola vez. Si la función no responde (caída o arranque en frío de más de 5 s), la fila se queda en revisión hasta que el administrador la decida. Si pasa seguido, agregar en una migración nueva un reintento periódico (pg_cron) de lo que lleve más de un minuto en revisión.
- **Calibrar con uso real** la heurística de spam (`spam.ts`) y la política (`politica_traza.ts`) en español coloquial: pueden marcar de más o de menos.
- **Coordinar con SCRUM-242 (eliminar publicaciones).** El retiro por el administrador de algo ya publicado debería anotarse en `moderaciones_foro` (una acción `retiro`) para no tener dos historiales.

## SCRUM-369: reportes de publicaciones del foro

**Qué quedó hecho:**

- `0036_foro_reportes.sql`: tabla `reportes_foro` con un reporte por usuario y publicación (`unique`), solo sobre lo `publicada` y ajeno. El autor no tiene ninguna policy sobre la tabla y la app nunca pide `reportante_id`. Trae su script de verificación para el SQL Editor.
- Botón "Reportar" en el detalle de una publicación ajena (motivo + detalle opcional, obligatorio con "Otro") y vista "Reportadas" en `/admin/foro`, con cuántos reportes tiene cada publicación y por qué.

**Qué falta:**

- **Actuar sobre lo reportado** es de SCRUM-242 (eliminar publicaciones). Hoy el administrador ve la bandeja y abre el detalle, pero no puede retirar la publicación ni descartar los reportes. Cuando exista la eliminación, conviene que la tarjeta de `_TarjetaReportada` (`lib/screens/admin/moderacion_foro_screen.dart`) ofrezca la misma acción, y que lo retirado deje de contar en "Reportadas" (filtrar por `publicaciones_foro.estado` en `reportes()` o en `PublicacionReportada.agrupar`).
- **Tiempo real.** `foroEnVivoProvider` no escucha `reportes_foro`: el administrador ve los reportes nuevos al deslizar para recargar o al volver a entrar. Si hace falta en vivo, agregar la tabla a la publicación de Realtime en una migración nueva (como `0028_foro_tiempo_real.sql`) y escucharla en `SupabaseCambiosForo`.
- **Comentarios.** La HU habla de publicaciones; los comentarios ofensivos no se pueden reportar.

## SCRUM-289 y SCRUM-247: las rutas de la portada y de Explorar rutas

**Qué quedó hecho:** `CarruselRutasCercanas` (`lib/widgets/carrusel_rutas_cercanas.dart`) asoma las rutas de la comunidad de lado en la portada, y "Ver todas" lleva a la sección de Rutas. Tocar una abre su detalle (SCRUM-240). Desde SCRUM-247, cada ruta va en `TarjetaRutaExplorar` (`lib/widgets/tarjeta_ruta_explorar.dart`), la misma tarjeta de la lista de Explorar rutas: miniatura del recorrido, nombre, dificultad, distancia, desnivel y quién la creó.

**Qué falta, y de quién depende:**

- **La cercanía en el carrusel.** Explorar rutas ya ordena por cercanía (SCRUM-246, con `rutas_cercanas` de 0037), pero el carrusel todavía muestra las últimas publicadas. Lo que falta es que `rutasCercanasProvider` (`lib/services/inicio_provider.dart`) use la misma consulta y la ubicación del usuario; el widget no cambia. Mientras tanto, el rótulo "RUTAS CERCANAS" promete más de lo que hace.
- **El desnivel.** No hay historia que lo produzca: los puntos GPS que guarda la app no llevan altitud, así que haría falta guardarla al entrenar o pedírsela a un servicio de elevación. Hasta entonces la tarjeta dice "Desnivel no disponible" (`TarjetaRutaExplorar.sinDesnivel`).

## SCRUM-363: clasificación de la ruta por un Runner Experto

**Qué quedó hecho:**

- `0045_clasificacion_de_rutas.sql`: `rutas.dificultad` y `clasificada_por`, los estados `clasificada` y `datos_incompletos`, y `preparar_ruta`, que manda la ruta a revisión si tiene distancia o la deja con la dificultad pendiente si no (criterio 3). El experto asigna con `clasificar_ruta` y el autor publica con `confirmar_publicacion_ruta`, las dos `security definer` (nadie actualiza `rutas` directo). Aviso `ruta_clasificada` para el autor. Trae su script de verificación para el SQL Editor.
- Bandeja "Rutas por clasificar" desde el Perfil del Runner Experto; en el detalle de la ruta, la dificultad para todos, el selector para el experto y el estado y el botón "Publicar ruta" para el autor.

Con esto, y los chips de SCRUM-266, la dificultad funciona de punta a punta: la guarda la base, `rutas_cercanas` y `buscar_rutas` la devuelven, Explorar rutas filtra por ella y el detalle la muestra.

**Qué falta:**

- **Pendiente y desnivel.** La HU los nombra, pero la app no guarda altitud (`0001`: "puntos_gps SIN altitud, a petición explícita"). Acordado con el equipo: el experto clasifica con la distancia y el mapa. Para usarlos haría falta guardar la altitud al entrenar o pedírsela a un servicio de elevación al guardar la ruta; con ellos, `preparar_ruta` podría exigirlos para "datos suficientes" y el detalle mostrarlos.
- **Completar los datos.** Una ruta en `datos_incompletos` se queda así: no hay de dónde sacar la distancia que le falta, y el índice de `0031` no deja volver a publicar ese entrenamiento (solo las rechazadas se pueden mandar de nuevo). Si se resuelve la distancia, haría falta una función que la recalcule y la pase a `en_revision`.
- **Rechazar una ruta.** No está en los criterios. `motivo_rechazo` y el aviso `ruta_rechazada` ya existen; faltaría una función `rechazar_ruta` como `clasificar_ruta` y su botón en el detalle.
- **Una policy ajena en la base.** La base compartida tenía `"el runner experto ve las rutas pendientes de su revision"` (`estado = 'revision_experto'`), que no está en ninguna migración del repo y en lugar de la de 0029. `0047_experto_ve_rutas_en_revision.sql` vuelve a poner la de 0029 sin borrar la otra. Falta averiguar en el grupo quién la creó: si nadie la usa, borrarla en una migración nueva (`drop policy "el runner experto ve las rutas pendientes de su revision" on rutas;`).
- **Tocar el aviso.** La bandeja de notificaciones no abre la ruta. El autor llega a confirmarla por "Ver mi ruta" en la pantalla de publicar de ese entrenamiento.

## SCRUM-259 (HU-35): revisar la clasificación del Runner Experto

**Qué quedó hecho:** la regla de quién puede revisar está en la base: `puede_revisar_clasificacion(ruta_id)` (0042, SCRUM-260) dice que sí a un Runner Experto que no sea el autor de la ruta. La pantalla de revisión (`lib/screens/rutas/revisar_clasificacion_screen.dart`, SCRUM-261) muestra la ruta, su dificultad propuesta y los datos en que se basa, y se abre desde el detalle de la ruta solo para quien puede revisar. Los botones de confirmar (SCRUM-262) y de elegir otra dificultad (SCRUM-263) ya están, y llaman a `confirmar_clasificacion` y a `corregir_clasificacion`; aparecen solo si la ruta tiene una dificultad propuesta, así que hoy no se ven. El detalle de la ruta muestra su dificultad y, si un Runner Experto la revisó, lo dice con la fecha (SCRUM-264); hoy todas van "Sin clasificar".

**Qué falta, y de quién depende:**

- **La función `confirmar_clasificacion` en la base.** Depende de que exista `rutas.dificultad` (SCRUM-363); la puede escribir quien haga la 363, o Steven cuando la columna exista. La app la llama así y espera esto:
  - `confirmar_clasificacion(p_ruta_id uuid)`, que no devuelve nada.
  - Solo la usa quien pase `puede_revisar_clasificacion(p_ruta_id)`. A los demás les responde con el error `42501`, que la app muestra como "Ya no puedes revisar esta ruta".
  - Si la ruta no tiene dificultad, no hay nada que confirmar: error `22023`.
  - Deja la ruta marcada como revisada, con quién y cuándo, sin cambiar la dificultad. Dónde se guarda eso —columnas nuevas en `rutas` o la fila de `revisiones_ruta` de la etapa `experto` (SCRUM-321)— está por acordar con el equipo.
  - Solo con sesión: quitársela a `public` y a `anon`, y dársela a `authenticated`.
- **La función `corregir_clasificacion` en la base**, con la misma dependencia. La app la llama así y espera esto:
  - `corregir_clasificacion(p_ruta_id uuid, p_dificultad text)`, que no devuelve nada. `p_dificultad` llega como `facil`, `moderada` o `dificil`; cualquier otro valor es error `22023`.
  - Los mismos permisos que `confirmar_clasificacion`: `puede_revisar_clasificacion(p_ruta_id)`, o error `42501`.
  - Reemplaza `rutas.dificultad` por `p_dificultad` y deja la ruta marcada como revisada, con quién y cuándo, donde se acuerde. Esa es su clasificación definitiva.
- **Registrar la revisión (SCRUM-264).** `confirmar_clasificacion` y `corregir_clasificacion` tienen que guardar quién revisó (`auth.uid()`) y cuándo (`now()`). La app lee el cuándo como `dificultad_revisada_en` en la fila de la ruta, y le da igual de dónde salga:
  - Puede ser una columna de `rutas`, con `dificultad_revisada_por` al lado.
  - O un campo calculado `dificultad_revisada_en(rutas)` que lo saque de `revisiones_ruta` (SCRUM-321), como `miniatura` en 0038.

  Cuando exista, hay que sumarlo a `_columnasConTrazado` de `SupabaseRutasRepository`, que es lo que pide el detalle. El quién no se le muestra a nadie: el criterio 5 pide decir que fue un Runner Experto, no cuál.
- **Quién propone la dificultad.** HU-35 dice que el experto revisa una dificultad ya propuesta; SCRUM-363 dice que el experto la asigna. Está por decidir con el equipo, y define qué muestra la pantalla como "propuesta".
- **El desnivel acumulado** que pide el criterio 2: la pantalla lo muestra como no disponible, por lo mismo que la tarjeta (ver "El desnivel" en la sección anterior).
