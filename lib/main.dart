import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/rutas_auth.dart';
import 'screens/home/inicio_screen.dart';
import 'screens/onboarding/perfil_screen.dart';
import 'screens/onboarding/permisos_screen.dart';
import 'screens/summary/resumen_screen.dart';
import 'screens/tracking/tracking_con_actividad_elegida.dart';
import 'supabase_config.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  runApp(const ProviderScope(child: TrazaApp()));
}

/// Pantalla con la que abre la app. Por defecto, el login.
///
/// En un celular o emulador no hay barra de direcciones. Para abrir directo
/// otra pantalla se elige al ejecutar:
///
/// ```bash
/// flutter run --dart-define=RUTA_INICIAL=/tracking
/// ```
const _rutaInicial = String.fromEnvironment(
  'RUTA_INICIAL',
  defaultValue: '/login',
);

/// Navegación entre pantallas de la app (no son endpoints: el backend es
/// Supabase).
final _navegacion = GoRouter(
  initialLocation: _rutaInicial,
  routes: [
    // Login, registro y recuperación de contraseña (SCRUM-32 a SCRUM-36).
    ...rutasAuth,
    GoRoute(path: '/perfil', builder: (context, state) => const PerfilScreen()),
    GoRoute(
      path: '/permisos',
      builder: (context, state) => const PermisosScreen(),
    ),
    GoRoute(path: '/inicio', builder: (context, state) => const InicioScreen()),
    // Entrenamiento en curso (SCRUM-102, de Aaron) con la actividad que el
    // usuario eligió en los chips del inicio (SCRUM-93).
    GoRoute(
      path: '/tracking',
      builder: (context, state) => const TrackingConActividadElegida(),
    ),
    // Resumen de la sesión recién finalizada (SCRUM-43). El id del
    // entrenamiento viaja en la ruta (SCRUM-122); sin sesión no hay id y se
    // usa `/resumen` a secas.
    GoRoute(
      path: '/resumen',
      builder: (context, state) => ResumenScreen.desdeRuta(state),
      routes: [
        GoRoute(
          path: ':entrenamientoId',
          builder: (context, state) => ResumenScreen.desdeRuta(state),
        ),
      ],
    ),
  ],
);

class TrazaApp extends StatelessWidget {
  const TrazaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TRAZA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _navegacion,
    );
  }
}
