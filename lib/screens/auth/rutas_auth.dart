import 'package:go_router/go_router.dart';

import 'forgot_password_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';

/// Rutas de autenticación. Viven aquí y no en `main.dart` para que las
/// pruebas de pantalla monten exactamente las mismas.
final rutasAuth = <GoRoute>[
  GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  GoRoute(
    path: '/registro',
    builder: (context, state) => const RegisterScreen(),
  ),
  // El correo ya escrito en el login viaja en `extra`.
  GoRoute(
    path: '/recuperar',
    builder: (context, state) =>
        ForgotPasswordScreen(correoInicial: state.extra as String? ?? ''),
  ),
  // El correo al que se envió el código viaja en `extra`.
  GoRoute(
    path: '/restablecer',
    builder: (context, state) =>
        ResetPasswordScreen(correo: state.extra as String? ?? ''),
  ),
];

/// Rutas que se pueden abrir sin haber iniciado sesión.
const rutasSinSesion = {'/login', '/registro', '/recuperar', '/restablecer'};

/// A dónde mandar a la persona según si tiene sesión guardada. `null` deja
/// seguir a [ruta].
///
/// - Sin sesión, cualquier pantalla de la app lleva al login: sin sesión, RLS
///   no deja leer ni guardar nada.
/// - Con sesión, abrir el login o el registro lleva directo a Inicio.
///
/// La recuperación de contraseña queda abierta aunque haya sesión: verificar el
/// código abre una sesión temporal y la persona tiene que poder terminar.
String? redireccionPorSesion({required bool haySesion, required String ruta}) {
  if (!haySesion && !rutasSinSesion.contains(ruta)) return '/login';
  if (haySesion && (ruta == '/login' || ruta == '/registro')) return '/inicio';
  return null;
}
