import 'package:go_router/go_router.dart';

import '../../widgets/solo_administrador.dart';
import 'revision_rutas_screen.dart';

/// La bandeja de revisión de rutas del administrador y su detalle
/// (SCRUM-327), tras la barrera de su rol (SCRUM-332, criterio 7 de
/// SCRUM-321). Se abre con `push` desde su panel.
///
/// La del Runner Experto es "Rutas por clasificar" (SCRUM-363).
///
/// Vive aquí y no suelta en `main.dart` para que las pruebas monten la misma
/// que la app, como hace `rutasAuth`.
///
/// La barrera es de presentación: quien impide de verdad leer o decidir lo
/// que no le toca es la base (las policies de `rutas` y
/// `decidir_revision_ruta`, 0043 y 0048).
final rutasRevision = GoRoute(
  path: RevisionRutasScreen.ruta,
  builder: (context, state) =>
      const SoloAdministrador(hijo: RevisionRutasScreen()),
  routes: [
    GoRoute(
      path: ':rutaId',
      builder: (context, state) => SoloAdministrador(
        hijo: RevisionRutaScreen(rutaId: state.pathParameters['rutaId']!),
      ),
    ),
  ],
);
