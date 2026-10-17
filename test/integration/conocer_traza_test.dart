// Pruebas de integración de la presentación de la app (SCRUM-282): se llega
// a ella desde el login, se ve completa, al salir se vuelve al origen y la
// invitación a registrarse lleva al registro.
//
// Monta las pantallas de verdad y las rutas de auth tal como las arma
// `main.dart`. Solo se reemplaza el service de autenticación, que es lo único
// que necesita red.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/presentacion_traza.dart';
import 'package:traza/screens/auth/conocer_traza_screen.dart';
import 'package:traza/screens/auth/login_screen.dart';
import 'package:traza/screens/auth/register_screen.dart';
import 'package:traza/screens/auth/rutas_auth.dart';
import 'package:traza/services/auth_service.dart';

class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.requiereOnboarding).thenReturn(false);
    // Quien abre la presentación desde el login todavía no tiene cuenta.
    when(() => auth.haySesion).thenReturn(false);
  });

  Future<void> abrirLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        ...rutasAuth,
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada')),
        ),
        GoRoute(
          path: '/perfil',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Perfil')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirPresentacion(WidgetTester tester) async {
    final enlace = find.byKey(LoginScreen.claveConocerTraza);
    await tester.ensureVisible(enlace);
    await tester.tap(enlace);
    await tester.pumpAndSettle();
  }

  testWidgets('desde el login se abre completa', (tester) async {
    await abrirLogin(tester);
    await abrirPresentacion(tester);

    expect(find.text(ConocerTrazaScreen.titulo), findsOneWidget);
    expect(find.text(PresentacionTraza.lema), findsOneWidget);
    expect(find.text(PresentacionTraza.queEs), findsOneWidget);

    // Los tres pasos y las cinco funciones, recorriéndola como el usuario.
    for (final paso in PasoTraza.values) {
      await tester.scrollUntilVisible(find.text(paso.texto), 200);
      expect(find.text(paso.texto), findsOneWidget, reason: paso.name);
    }
    for (final funcion in FuncionTraza.values) {
      await tester.scrollUntilVisible(find.text(funcion.titulo), 200);
      expect(find.text(funcion.titulo), findsOneWidget, reason: funcion.name);
    }
  });

  testWidgets('al salir se vuelve al login', (tester) async {
    await abrirLogin(tester);
    await abrirPresentacion(tester);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ConocerTrazaScreen), findsNothing);
  });

  testWidgets('el gesto de atrás del sistema también devuelve al login', (
    tester,
  ) async {
    // La flecha no es la única salida: en Android se sale con el gesto.
    await abrirLogin(tester);
    await abrirPresentacion(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ConocerTrazaScreen), findsNothing);
  });

  testWidgets('la invitación lleva al registro (SCRUM-281)', (tester) async {
    await abrirLogin(tester);
    await abrirPresentacion(tester);

    final boton = find.byKey(ConocerTrazaScreen.claveCrearCuenta);
    await tester.scrollUntilVisible(boton, 200);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('con sesión abierta no se invita a registrarse', (tester) async {
    // A quien ya tiene cuenta, ofrecerle crearla no le dice nada.
    when(() => auth.haySesion).thenReturn(true);

    await abrirLogin(tester);
    await abrirPresentacion(tester);
    await tester.scrollUntilVisible(find.text(FuncionTraza.rutas.titulo), 200);

    expect(
      find.byKey(ConocerTrazaScreen.claveCrearCuenta, skipOffstage: false),
      findsNothing,
    );
    expect(find.text(PresentacionTraza.invitacion), findsNothing);
  });
}
