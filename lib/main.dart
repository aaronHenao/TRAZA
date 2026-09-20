import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/rutas_auth.dart';
import 'screens/history/historial_screen.dart';
import 'screens/home/actividad_screen.dart';
import 'screens/home/inicio_screen.dart';
import 'widgets/navegacion_principal.dart';
import 'screens/onboarding/perfil_screen.dart';
import 'screens/onboarding/permisos_screen.dart';
import 'screens/summary/resumen_screen.dart';
import 'screens/tracking/tracking_con_actividad_elegida.dart';
import 'services/auth_service.dart';
import 'supabase_config.dart';
import 'theme/app_theme.dart';
import 'widgets/ofrece_permiso_salud.dart';
import 'widgets/requiere_permiso_ubicacion.dart';

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
  // Se evalúa en cada cambio de pantalla. Supabase guarda la sesión en el
  // dispositivo y la restaura en `Supabase.initialize`, así que al abrir la
  // app ya se sabe si hay alguien con sesión iniciada.
  redirect: (context, state) {
    final auth = Supabase.instance.client.auth;
    return redireccionPorSesion(
      haySesion: auth.currentSession != null,
      ruta: state.matchedLocation,
      requiereOnboarding: AuthService.requiereOnboardingDe(auth.currentUser),
    );
  },
  routes: [
    // Login, registro y recuperación de contraseña (SCRUM-32 a SCRUM-36).
    ...rutasAuth,
    GoRoute(
      path: '/perfil',
      builder: (context, state) {
        // Durante el onboarding no lleva barra: la portada todavía no es un
        // destino válido y el flujo sigue a Permisos.
        if (AuthService.requiereOnboardingDe(
          Supabase.instance.client.auth.currentUser,
        )) {
          return const PerfilScreen(enOnboarding: true);
        }
        return const NavegacionPrincipal(
          seccion: SeccionPrincipal.perfil,
          child: PerfilScreen(),
        );
      },
    ),
    GoRoute(
      path: '/permisos',
      builder: (context, state) => const PermisosScreen(),
    ),
    // Portada: a donde se llega al entrar y terminar el onboarding.
    GoRoute(path: '/inicio', builder: (context, state) => const InicioScreen()),
    // Elegir el tipo de actividad y arrancar el entrenamiento (SCRUM-39).
    GoRoute(
      path: '/actividad',
      builder: (context, state) => const ActividadScreen(),
    ),
    // Entrenamientos anteriores (SCRUM-44).
    GoRoute(
      path: '/historial',
      builder: (context, state) => const NavegacionPrincipal(
        seccion: SeccionPrincipal.historial,
        child: HistorialScreen(),
      ),
    ),
    // Entrenamiento en curso (SCRUM-102, de Aaron) con la actividad que el
    // usuario eligió en los chips del inicio (SCRUM-93).
    GoRoute(
      path: '/tracking',
      // Sin permiso de ubicación no se abre: explica por qué y lo pide
      // (SCRUM-82). Después ofrece el de salud, que es opcional (SCRUM-83).
      builder: (context, state) => const RequierePermisoUbicacion(
        child: OfrecePermisoSalud(child: TrackingConActividadElegida()),
      ),
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
