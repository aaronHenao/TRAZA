import 'package:go_router/go_router.dart';

import '../../features/actividad/presentation/inicio_screen.dart';
import '../../features/perfil/presentation/perfil_screen.dart';
import '../../features/permisos/presentation/permisos_screen.dart';
import '../../screens/tracking/tracking_screen.dart';
import 'rutas.dart';

/// Router de la app.
///
/// El flujo definitivo arranca en registro/login (SCRUM-32 a SCRUM-36); mientras
/// esas pantallas no existan, la app abre directamente en el perfil.
final appRouter = GoRouter(
  initialLocation: Rutas.perfil,
  routes: [
    GoRoute(
      path: Rutas.perfil,
      builder: (context, state) => const PerfilScreen(),
    ),
    GoRoute(
      path: Rutas.permisos,
      builder: (context, state) => const PermisosScreen(),
    ),
    GoRoute(
      path: Rutas.inicio,
      builder: (context, state) => const InicioScreen(),
    ),
    // Entrenamiento en curso (SCRUM-102, de Aaron). Por ahora abre con la
    // actividad por defecto; la que el usuario elige en los chips del inicio
    // llega con SCRUM-93.
    GoRoute(
      path: Rutas.tracking,
      builder: (context, state) => const TrackingScreen(),
    ),
  ],
);
