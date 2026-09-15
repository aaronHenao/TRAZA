import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/screens/auth/login_screen.dart';
import 'package:traza/screens/auth/rutas_auth.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/widgets/boton_cerrar_sesion.dart';

class _MockAuthService extends Mock implements AuthService {}

Widget _app(AuthService auth) {
  final router = GoRouter(
    initialLocation: '/inicio',
    routes: [
      ...rutasAuth,
      GoRoute(
        path: '/inicio',
        builder: (context, state) =>
            const Scaffold(body: Center(child: BotonCerrarSesion())),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authServiceProvider.overrideWithValue(auth)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.cerrarSesion()).thenAnswer((_) async {});
  });

  testWidgets('confirmar cierra la sesión y vuelve al login', (tester) async {
    await tester.pumpWidget(_app(auth));

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cerrar sesión?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();

    verify(() => auth.cerrarSesion()).called(1);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('cancelar no cierra la sesión', (tester) async {
    await tester.pumpWidget(_app(auth));

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => auth.cerrarSesion());
    expect(find.byType(BotonCerrarSesion), findsOneWidget);
  });
}
