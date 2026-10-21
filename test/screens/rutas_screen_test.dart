import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/widgets/navegacion_principal.dart';

/// Pruebas de la sección de Rutas (SCRUM-284).
///
/// Es provisional: lo único que tiene que hacer hoy es existir, decir por qué
/// está vacía y dejar la barra usable. Lo que muestre lo traen HU-29 y las
/// suyas.
void main() {
  testWidgets('explica que las rutas todavía no están', (tester) async {
    await _montar(tester);

    expect(find.text('Rutas'), findsWidgets);
    expect(find.text('Las rutas llegan pronto'), findsOneWidget);
    expect(
      find.textContaining('recorridos que publique la comunidad'),
      findsOneWidget,
    );
  });

  testWidgets('lleva la barra con la sección marcada', (tester) async {
    await _montar(tester);

    expect(find.byType(NavegacionPrincipal), findsOneWidget);
    final barra = tester.widget<NavegacionPrincipal>(
      find.byType(NavegacionPrincipal),
    );
    expect(barra.seccion, SeccionPrincipal.rutas);
  });

  testWidgets('desde aquí se puede ir a otra sección', (tester) async {
    // La pantalla esté vacía o no, la barra tiene que seguir funcionando.
    final router = await _montar(tester);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/perfil');
  });

  testWidgets('no se rompe en la pantalla más estrecha', (tester) async {
    await _montar(tester, tamano: const Size(320, 568));

    expect(find.text('Las rutas llegan pronto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<GoRouter> _montar(
  WidgetTester tester, {
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: RutasScreen.ruta,
    routes: [
      GoRoute(path: RutasScreen.ruta, builder: (_, _) => const RutasScreen()),
      // Las demás secciones, de mentira: aquí solo importa poder salir.
      for (final seccion in SeccionPrincipal.values)
        if (seccion != SeccionPrincipal.rutas)
          GoRoute(
            path: seccion.ruta,
            builder: (_, _) => Scaffold(body: Text('En ${seccion.etiqueta}')),
          ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}
