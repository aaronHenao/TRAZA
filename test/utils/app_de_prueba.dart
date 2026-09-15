import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/screens/auth/rutas_auth.dart';
import 'package:traza/services/auth_service.dart';

/// App mínima para probar las pantallas de autenticación: las mismas rutas de
/// auth que `main.dart`, con el service falso y pantallas de mentira para
/// Inicio y Perfil, que son de otras HU.
Widget appDePrueba({
  required AuthService auth,
  required String ruta,
  Object? extra,
}) {
  final router = GoRouter(
    initialLocation: ruta,
    initialExtra: extra,
    routes: [
      ...rutasAuth,
      GoRoute(
        path: '/inicio',
        builder: (context, state) =>
            const Scaffold(body: Text('Pantalla Inicio')),
      ),
      GoRoute(
        path: '/perfil',
        builder: (context, state) =>
            const Scaffold(body: Text('Pantalla Perfil')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authServiceProvider.overrideWithValue(auth)],
    child: MaterialApp.router(routerConfig: router),
  );
}
