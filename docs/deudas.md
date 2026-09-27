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
