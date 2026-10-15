// Pruebas de integración de la presentación de la app (SCRUM-282): se llega
// a ella desde sus dos accesos —el login y el perfil— y al salir se vuelve
// a donde se entró.
//
// Monta las dos pantallas de verdad y las rutas de auth tal como las arma
// `main.dart`. Solo se reemplaza lo que depende de la red: el service de
// autenticación y los repositorios del perfil.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/presentacion_traza.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/screens/auth/conocer_traza_screen.dart';
import 'package:traza/screens/auth/login_screen.dart';
import 'package:traza/screens/auth/rutas_auth.dart';
import 'package:traza/screens/onboarding/perfil_screen.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/insignias_service.dart';
import 'package:traza/services/objetivos_service.dart';

import '../utiles/insignias_falsas.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Repositorio de objetivos que no sale a la red: el perfil solo tiene que
/// llegar a pintarse.
class _ObjetivosFalsos implements ObjetivosRepository {
  @override
  Future<Map<TipoObjetivo, num>> cargar() async => const {};

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {}
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.requiereOnboarding).thenReturn(false);
  });

  Future<void> abrir(WidgetTester tester, String ruta) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: ruta,
      routes: [
        ...rutasAuth,
        GoRoute(path: '/perfil', builder: (_, _) => const PerfilScreen()),
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          objetivosRepositoryProvider.overrideWithValue(_ObjetivosFalsos()),
          insigniasRepositoryProvider.overrideWithValue(InsigniasFalsas()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Comprueba que la presentación está completa: identidad, qué es y las
  /// cinco funciones, recorriéndola como lo haría el usuario.
  Future<void> comprobarQueEstaCompleta(WidgetTester tester) async {
    expect(find.text(ConocerTrazaScreen.titulo), findsOneWidget);
    expect(find.text(PresentacionTraza.lema), findsOneWidget);
    expect(find.text(PresentacionTraza.queEs), findsOneWidget);

    for (final funcion in FuncionTraza.values) {
      await tester.scrollUntilVisible(find.text(funcion.titulo), 200);
      expect(find.text(funcion.titulo), findsOneWidget, reason: funcion.name);
    }
  }

  testWidgets('desde el login se abre completa y se vuelve al login', (
    tester,
  ) async {
    await abrir(tester, '/login');

    await tester.ensureVisible(find.byKey(LoginScreen.claveConocerTraza));
    await tester.tap(find.byKey(LoginScreen.claveConocerTraza));
    await tester.pumpAndSettle();

    await comprobarQueEstaCompleta(tester);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PerfilScreen), findsNothing);
  });

  testWidgets('desde el perfil se abre completa y se vuelve al perfil', (
    tester,
  ) async {
    await abrir(tester, '/perfil');

    await tester.scrollUntilVisible(
      find.byKey(PerfilScreen.claveConocerTraza),
      200,
    );
    await tester.tap(find.byKey(PerfilScreen.claveConocerTraza));
    await tester.pumpAndSettle();

    await comprobarQueEstaCompleta(tester);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(PerfilScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('el gesto de atrás del sistema también devuelve al origen', (
    tester,
  ) async {
    // La flecha no es la única salida: en Android se sale con el gesto.
    await abrir(tester, '/perfil');

    await tester.scrollUntilVisible(
      find.byKey(PerfilScreen.claveConocerTraza),
      200,
    );
    await tester.tap(find.byKey(PerfilScreen.claveConocerTraza));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ConocerTrazaScreen), findsNothing);
    expect(find.byType(PerfilScreen), findsOneWidget);
  });

  testWidgets('entrar desde un sitio y después desde el otro no mezcla el '
      'regreso', (tester) async {
    // La pantalla no recuerda de dónde vino: vuelve a lo que haya debajo.
    await abrir(tester, '/login');

    await tester.ensureVisible(find.byKey(LoginScreen.claveConocerTraza));
    await tester.tap(find.byKey(LoginScreen.claveConocerTraza));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await abrir(tester, '/perfil');

    await tester.scrollUntilVisible(
      find.byKey(PerfilScreen.claveConocerTraza),
      200,
    );
    await tester.tap(find.byKey(PerfilScreen.claveConocerTraza));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(PerfilScreen), findsOneWidget);
  });
}
