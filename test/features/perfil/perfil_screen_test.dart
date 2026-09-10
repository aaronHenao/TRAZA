import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:traza/core/router/rutas.dart';
import 'package:traza/features/perfil/presentation/perfil_controller.dart';
import 'package:traza/features/perfil/presentation/perfil_screen.dart';
import 'package:traza/features/permisos/presentation/permisos_screen.dart';

/// Pruebas de la interfaz de perfil (SCRUM-86). La cobertura completa de la
/// gestión de objetivos llega en SCRUM-128.
void main() {
  testWidgets('muestra el estado vacío cuando no hay objetivos seleccionados', (
    tester,
  ) async {
    await _montarPerfil(tester);

    expect(find.text('Aún no has elegido objetivos'), findsOneWidget);
    expect(find.text('Distancia semanal'), findsOneWidget);
    expect(find.text('Frecuencia de entrenamiento'), findsOneWidget);
  });

  testWidgets('permite seleccionar varios objetivos a la vez', (tester) async {
    await _montarPerfil(tester);

    await tester.tap(find.text('Distancia semanal'));
    await tester.pump();

    expect(find.text('Aún no has elegido objetivos'), findsNothing);

    await tester.tap(find.text('Frecuencia de entrenamiento'));
    await tester.pump();

    final controlador = _controladorDe(tester);
    expect(controlador.seleccionados, hasLength(2));
  });

  testWidgets('al desmarcar el último objetivo vuelve el estado vacío', (
    tester,
  ) async {
    await _montarPerfil(tester);

    await tester.tap(find.text('Distancia semanal'));
    await tester.pump();
    await tester.tap(find.text('Distancia semanal'));
    await tester.pump();

    expect(find.text('Aún no has elegido objetivos'), findsOneWidget);
    expect(_controladorDe(tester).sinObjetivos, isTrue);
  });

  testWidgets('el botón Continuar navega a la pantalla de permisos', (
    tester,
  ) async {
    await _montarPerfil(tester);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.byType(PermisosScreen), findsOneWidget);
  });
}

Future<void> _montarPerfil(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: Rutas.perfil,
    routes: [
      GoRoute(path: Rutas.perfil, builder: (_, _) => const PerfilScreen()),
      GoRoute(path: Rutas.permisos, builder: (_, _) => const PermisosScreen()),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => PerfilController(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

PerfilController _controladorDe(WidgetTester tester) =>
    Provider.of<PerfilController>(
      tester.element(find.byType(PerfilScreen)),
      listen: false,
    );
