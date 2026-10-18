import 'package:go_router/go_router.dart';

import '../../models/revision_ruta.dart';
import '../../widgets/solo_administrador.dart';
import '../../widgets/solo_experto.dart';
import 'revision_rutas_screen.dart';

/// Las rutas de las bandejas de revisión de rutas, cada una tras la barrera de
/// su rol (SCRUM-332, criterio 7 de SCRUM-321).
///
/// Viven aquí y no sueltas en `main.dart` para que las pruebas monten las
/// mismas que la app, como hace `rutasAuth`.
///
/// Las barreras son de presentación: quien impide de verdad leer o decidir lo
/// que no le toca es la base (las policies de `rutas` y
/// `decidir_revision_ruta`, 0036).
final rutasRevision = <RouteBase>[
  // Primera revisión, la del administrador (SCRUM-327). Se abre con `push`
  // desde su panel.
  GoRoute(
    path: EtapaRevision.administrador.ruta,
    builder: (context, state) => const SoloAdministrador(
      hijo: RevisionRutasScreen(etapa: EtapaRevision.administrador),
    ),
    routes: [
      GoRoute(
        path: ':rutaId',
        builder: (context, state) => SoloAdministrador(
          hijo: RevisionRutaScreen(
            rutaId: state.pathParameters['rutaId']!,
            etapa: EtapaRevision.administrador,
          ),
        ),
      ),
    ],
  ),
  // Segunda revisión, la del Runner Experto (SCRUM-329). Se abre con `push`
  // desde su pantalla.
  GoRoute(
    path: EtapaRevision.experto.ruta,
    builder: (context, state) => const SoloExperto(
      hijo: RevisionRutasScreen(etapa: EtapaRevision.experto),
    ),
    routes: [
      GoRoute(
        path: ':rutaId',
        builder: (context, state) => SoloExperto(
          hijo: RevisionRutaScreen(
            rutaId: state.pathParameters['rutaId']!,
            etapa: EtapaRevision.experto,
          ),
        ),
      ),
    ],
  ),
];
