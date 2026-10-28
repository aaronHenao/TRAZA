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
  - si se borra la fila (los comentarios caen con ella por el `on delete cascade` de `comentarios_foro`) o se marca `estado = 'eliminada'`, que ya existe y oculta la publicación sin perder el rastro para la moderación. Lo segundo choca con el trigger de 0024 y 0025, que no deja cambiar el estado; la salida está en `retirar_publicacion_foro` (0052, SCRUM-242): una función `security definer` que anuncia `traza.moderando` para que el trigger la deje pasar. Si se borra la fila, el historial de versiones también se va (`on delete cascade`).
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

- **Descartar un reporte sin retirar la publicación.** Si el administrador la revisa y decide que no incumple nada, no tiene cómo quitarla de la bandeja: solo sale de ahí cuando se retira (SCRUM-242). Haría falta marcar el reporte como revisado, con una columna nueva en `reportes_foro` y un filtro en `reportes()`.
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

- `0048_flujo_unico_de_revision.sql`: une esta HU con SCRUM-321, que dejó en la base (a mano, sin migración en el repo) una revisión en dos etapas. El camino queda así: publicar → `en_revision` (espera al administrador) → `revision_experto` (espera al Runner Experto) → `clasificada` (el experto aprobó asignando la dificultad) → `publicada` (el autor confirmó). El administrador y el experto pueden rechazar con motivo (`decidir_revision_ruta`). El experto ya no aprueba por `decidir_revision_ruta`: aprobar es `clasificar_ruta`, que ahora parte de `revision_experto` y deja su fila en `revisiones_ruta`. Quita la policy de 0047 (`en_revision` ahora es del administrador). Trae su script de verificación, que recorre el flujo completo y los rechazos.

Con esto, y los chips de SCRUM-266, la dificultad funciona de punta a punta: la guarda la base, `rutas_cercanas` y `buscar_rutas` la devuelven, Explorar rutas filtra por ella y el detalle la muestra.

**Qué falta:**

- **Pendiente y desnivel.** La HU los nombra, pero la app no guarda altitud (`0001`: "puntos_gps SIN altitud, a petición explícita"). Acordado con el equipo: el experto clasifica con la distancia y el mapa. Para usarlos haría falta guardar la altitud al entrenar o pedírsela a un servicio de elevación al guardar la ruta; con ellos, `preparar_ruta` podría exigirlos para "datos suficientes" y el detalle mostrarlos.
- **Completar los datos.** Una ruta en `datos_incompletos` se queda así: no hay de dónde sacar la distancia que le falta, y el índice de `0031` no deja volver a publicar ese entrenamiento (solo las rechazadas se pueden mandar de nuevo). Si se resuelve la distancia, haría falta una función que la recalcule y la pase a `en_revision`.
- **Los scripts de verificación de 0045 y 0047** describen el flujo de antes (el experto clasifica desde `en_revision`): después de `0048` fallan a propósito. El que vale es el de `0048`.
- **Tocar el aviso.** La bandeja de notificaciones no abre la ruta. El autor llega a confirmarla por "Ver mi ruta" en la pantalla de publicar de ese entrenamiento.

## SCRUM-321: validar la publicación de rutas (administrador y Runner Experto)

**Qué quedó hecho:**

- `0043_revision_de_rutas.sql` y `0044_aviso_de_ruta_rechazada.sql`: lo que `0048` daba por hecho en la base (`revisiones_ruta`, `decidir_revision_ruta`, `avisar_ruta_rechazada` y la policy del experto sobre `revision_experto`). Se escribieron como 0036 y 0037 y se aplicaron a mano en la base compartida antes de llegar al repo; llevan esos números porque `0048` depende de ellas y para entonces 0036 y 0037 ya estaban usados. **En la base compartida no hay que volver a correrlas.**
- App: bandeja del administrador (`/admin/rutas`, desde su panel) con su detalle y el trazado, para aprobar o rechazar con motivo. Lo que aprueba pasa a "Rutas por clasificar" (SCRUM-363). El Runner Experto rechaza con motivo desde el detalle de la ruta, junto a "Asignar dificultad", que es su aprobación. El diálogo del motivo es `pedirMotivoRechazo`.

**Qué falta:**

- **Las bandejas no son en tiempo real**: la del administrador se actualiza al entrar, al deslizar y al decidir. `rutas` no está en la publicación de Realtime.
- **Unificar el diálogo de rechazo** (`pedirMotivoRechazo`) con el `_DialogoRechazo` privado de la moderación del foro, que hace lo mismo con otro texto.
- **El administrador no puede corregir una decisión**: una ruta rechazada no vuelve a revisión. El autor puede volver a publicar el mismo entrenamiento (el índice de 0031 deja fuera las rechazadas).

## SCRUM-259 (HU-35): revisar la clasificación del Runner Experto

**Qué quedó hecho:**

- `0042_permiso_revisar_clasificacion.sql` (SCRUM-260): `puede_revisar_clasificacion(ruta_id)`, la regla de quién puede revisar, en un solo lugar.
- `0054_revisar_clasificacion.sql`: encaja HU-35 en el flujo de 0048 sin cambiarlo. El equipo acordó que la revisión la haga el mismo Runner Experto que clasificó la ruta: con la ruta ya publicada, confirma o corrige esa dificultad, y lo que deje es la clasificación definitiva, porque se revisa una sola vez.
  - `puede_revisar_clasificacion` queda más estricta: el Runner Experto que la clasificó, en una ruta publicada, con dificultad y sin revisar.
  - `confirmar_clasificacion(p_ruta_id)` y `corregir_clasificacion(p_ruta_id, p_dificultad)`, `security definer`. Responden `42501` a quien no puede, también si ya se revisó (aunque sea desde otro teléfono al mismo tiempo), y `22023` a una dificultad que no es `facil`, `moderada` ni `dificil`. Corregir cambia `rutas.dificultad`; lo demás de `rutas` no se toca.
  - La revisión queda en su propia tabla, `revisiones_clasificacion`: una fila por ruta, con quién la revisó, la dificultad que tenía y cuándo. No tiene policies: la app no la lee ni la escribe directo, y pregunta la fecha con `clasificacion_revisada_en(p_ruta_id)`. Quién la revisó no sale de la base.
  - Trae su script de verificación para el SQL Editor. Se probó contra un PostgreSQL local con todas las migraciones del repo, y el script de 0048 sigue dando OK con la 0054 encima.
- App: la pantalla de revisión (SCRUM-261) con la ruta, su dificultad y los datos en que se basa; confirmar (SCRUM-262); elegir otra dificultad (SCRUM-263); y en el detalle, la dificultad con "Revisada por un Runner Experto · fecha" (SCRUM-264). La fecha se pregunta aparte de la ruta, así que las consultas del detalle y de publicar no cambian. Mientras llega, o si no se pudo saber, la tarjeta no dice ni que sí ni que no.

**Qué falta:**

- **El desnivel acumulado** que pide el criterio 2: la pantalla lo muestra como no disponible, por lo mismo que la tarjeta (ver "El desnivel" en SCRUM-289 y SCRUM-247).
- **Revisar no le avisa al autor**: HU-35 no lo pide. Si el equipo lo quiere, es un tipo de aviso nuevo y una llamada a `crear_notificacion` en `corregir_clasificacion`.

## SCRUM-374: recompensas

**Qué quedó hecho:**

- `0049_recompensas.sql`: tabla `recompensas` (nombre, descripción, puntos entre 1 y 1 000 000, disponible). Los corredores leen solo lo disponible; crear es solo de `es_admin()`. Trae su script de verificación para el SQL Editor.
- Gestión del administrador (`/admin/recompensas`, desde el Panel) con su formulario, y catálogo del corredor (`/recompensas`, desde Inicio) con los puntos de cada recompensa.

**Qué falta:**

- **Canjear no existe, ni los puntos del corredor.** Ninguna HU de la Persona 4 dice de dónde salen los puntos (¿la XP?, ¿una moneda aparte?) ni cómo se canjea. La tabla `canjes_recompensa` ya existe (SCRUM-380, ver abajo); el flujo de canjear es de otra HU.
- **Cambiar la disponibilidad.** Se elige al crear; ninguna HU pide cambiarla después. Si hace falta, la policy de update de `0050_canjes_recompensa.sql` ya lo permite al administrador: falta un interruptor en la tarjeta de la gestión.
- **`_Campo` repetido.** `formulario_recompensa_screen.dart` es la quinta copia (junto a `formulario_nivel_screen.dart`, `formulario_reto_screen.dart`, `nueva_publicacion_screen.dart` y `publicar_ruta_screen.dart`). Falta un campo de formulario compartido en `lib/widgets/`.

## SCRUM-380: cambiar los puntos de una recompensa

**Qué quedó hecho:**

- `0050_canjes_recompensa.sql`: policy de update de `recompensas` para el administrador y tabla `canjes_recompensa`. Cada canje guarda los puntos que costó: el trigger `preparar_canje_recompensa` los copia del precio vigente al insertar (lo que mande el cliente se ignora) y `proteger_canje_recompensa` los deja fijos en cualquier update. Trae su script de verificación para el SQL Editor.
- Botón "Cambiar puntos" en cada tarjeta de la gestión, con un diálogo que no guarda una cantidad inválida.

**Qué falta:**

- **El flujo de canjear.** Nadie inserta en `canjes_recompensa` todavía (no hay policy de insert). La HU que lo haga debería:
  - entrar por una función `security definer` con `set search_path = public` que valide `auth.uid()`;
  - no calcular el precio a mano: el trigger ya lo pone, y descontar del saldo el `puntos_canjeados` que devuelve el `insert ... returning`;
  - bloquear la recompensa (`select ... from recompensas where id = $1 and disponible for share`) para que un cambio de precio a la mitad no deje el saldo validado contra un valor y el canje con otro, y bloquear por usuario contra canjes dobles;
  - traducir el `23503` del trigger (la recompensa no existe o fue retirada, desde SCRUM-385).
- **El criterio 3 solo se verifica en SQL** hasta que exista el canje: no hay pantalla de "mis canjes".

## SCRUM-385: eliminar recompensas

**Qué quedó hecho:**

- `0051_retirada_recompensas.sql`: eliminar es retirar (`recompensas.retirada_en`), no borrar, para que los canjes sigan apuntando a su recompensa. La fecha la pone la base y no se puede quitar. Quien la canjeó la sigue pudiendo leer para su historial; los demás ya no la ven. El trigger del canje rechaza las retiradas. Trae su script de verificación para el SQL Editor.
- Botón "Eliminar" en cada tarjeta de la gestión, con confirmación explícita. El catálogo y la gestión dejan de mostrar las retiradas.

**Qué falta:**

- **Historial de canjes del corredor.** El criterio 3 se cumple en la base (el canje y su recompensa siguen ahí y él los puede leer), pero no hay pantalla de "mis canjes": llega con la HU de canjear.
- **Ver lo retirado.** La gestión no muestra las recompensas eliminadas. Si el administrador necesita consultarlas, iría una pestaña "Retiradas" como la de la gestión de retos, con una consulta que no filtre `retirada_en`.

## SCRUM-242: eliminar publicaciones del foro

**Qué quedó hecho:**

- `0052_foro_retirar_publicacion.sql`: eliminar es retirar (`estado = 'eliminada'`, que ya existía desde 0035), no borrar, para que la bitácora y los reportes que la señalaron sigan teniendo a qué apuntar. `retirar_publicacion_foro` hace las tres cosas en una transacción —retira, asienta y avisa— y es lo único que puede cambiar el estado: `publicaciones_foro` no tiene policy de update, así que la función corre como su dueño y anuncia `traza.moderando` para que el trigger `proteger_publicacion_foro` la deje pasar, igual que `resolver_moderacion` (0035). Trae su script de verificación para el SQL Editor, con la cabecera para hacerse pasar por un usuario.
- Bitácora `bitacora_moderacion_foro` (criterio 3): publicación, administrador, su nombre copiado en ese momento, motivo y fecha que pone la base. Solo el administrador la lee, y nadie la escribe desde la app. `moderaciones_foro` no servía para esto: es la cola de lo que espera veredicto antes de publicarse, no el registro de lo que se retiró después.
- Botón "Eliminar" en las dos pestañas del panel —*Publicadas* y *Reportadas*—, con un diálogo que confirma y pide el motivo en el mismo paso; sin motivo no se llega a tocar la base. Lo retirado sale del foro, de *Publicadas* y de la bandeja de *Reportadas*.
- El autor recibe el aviso `publicacion_retirada` con el motivo (criterio 2), y tocarlo en la bandeja abre su publicación, donde lee por qué la retiramos. Es el único aviso que abre algo: los de rutas siguen sin llevar a ningún lado (ver SCRUM-363).

**Qué falta:**

- **Leer la bitácora desde la app.** Hoy solo se consulta por SQL, y se acordó así: el criterio pide registrar, no mostrar, y el administrador son los cuatro del equipo, con acceso al dashboard. Si se quiere en pantalla, **no hace falta migración**: la tabla y su policy de lectura ya están, y bastaría un `select` en el repositorio y una pestaña, con `administrador_nombre` que ya viene copiado. La consulta para auditar a mano:
  ```sql
  select b.fecha, b.administrador_nombre, b.motivo, p.titulo, p.autor_nombre
  from bitacora_moderacion_foro b
  join publicaciones_foro p on p.id = b.publicacion_id
  order by b.fecha desc;
  ```
- **Un asiento no sobrevive a un borrado a mano.** `publicacion_id` tiene `on delete cascade`, así que si alguien borrara la fila de la publicación por SQL, su asiento se iría con ella. Está así a propósito para no dejar asientos huérfanos, y desde la app es imposible: no hay policy de delete en `publicaciones_foro`, y retirar es precisamente lo contrario a borrar.
- **Restituir.** No hay forma de deshacer un retiro desde la app; se hace por SQL, con las dos sentencias de `traza.moderando` en la misma ejecución (está al pie de 0052). La bitácora tampoco registraría la restitución: hoy solo asienta retiros, y una acción nueva pediría su columna `accion`.
- **Comentarios.** La HU habla de publicaciones, así que un comentario ofensivo no se puede retirar por separado (los de una publicación retirada desaparecen con ella, por la policy de 0035). `comentarios_foro` ya admite `estado = 'eliminada'` desde 0035, así que sería el mismo patrón: una función hermana y su asiento.

