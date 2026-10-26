import 'package:go_router/go_router.dart';

import '../../models/resumen_entrenamiento.dart';
import '../../models/ruta.dart';
import 'detalle_ruta_screen.dart';
import 'publicar_ruta_screen.dart';
import 'revisar_clasificacion_screen.dart';
import 'rutas_screen.dart';

/// La sección de Rutas: Explorar rutas y lo que se abre desde ella
/// (SCRUM-250).
///
/// Vive aquí y no en `main.dart` para que las pruebas monten exactamente la
/// misma, como las rutas de autenticación.
///
/// Publicar y el detalle van anidados bajo Explorar, como los de retos y los
/// del foro: si se llega a uno por un enlace, debajo queda la lista y "atrás"
/// vuelve a ella. Abiertos con `push`, que es como los abre la app, se apilan
/// solos sobre la pantalla en la que estaba el usuario, y al cerrarlos se
/// vuelve ahí.
final seccionRutas = GoRoute(
  path: RutasScreen.ruta,
  builder: (context, state) => const RutasScreen(),
  routes: [
    // Publicar como ruta el recorrido de un entrenamiento (SCRUM-241). Se
    // abre con `push` desde el resumen, que ya tiene el entrenamiento
    // cargado y lo manda por `extra`: pedirlo otra vez por id sería
    // consultar dos veces lo mismo. Sin él no hay recorrido que publicar, y
    // la pantalla lo dice en vez de reventar.
    //
    // Antes de ':rutaId': si no, 'publicar' se tomaría por el id de una ruta
    // y se abriría su detalle.
    GoRoute(
      path: 'publicar',
      builder: (context, state) =>
          PublicarRutaScreen(resumen: state.extra as ResumenEntrenamiento?),
    ),
    // El detalle de una ruta de la comunidad (SCRUM-240). Se abre con `push`
    // desde Explorar rutas, el carrusel de la portada y el apartado de rutas
    // del foro, así al cerrarlo se vuelve a donde estaba. Explorar y el
    // carrusel mandan en `extra` la ruta elegida (SCRUM-250), para mostrar
    // lo que ya se sabe de ella mientras llega su trazado; sin ella, el
    // detalle la pide por su id.
    GoRoute(
      path: ':rutaId',
      builder: (context, state) => DetalleRutaScreen(
        rutaId: state.pathParameters['rutaId']!,
        vistaPrevia: state.extra as Ruta?,
      ),
      routes: [
        // Revisar su clasificación (SCRUM-261): solo para un Runner Experto
        // que no sea el autor. Se abre con `push` desde el detalle, así que
        // "atrás" vuelve a él.
        GoRoute(
          path: 'revisar',
          builder: (context, state) => RevisarClasificacionScreen(
            rutaId: state.pathParameters['rutaId']!,
          ),
        ),
      ],
    ),
  ],
);
