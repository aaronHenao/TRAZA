import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/screens/admin/gestion_niveles_screen.dart';
import 'package:traza/screens/admin/gestion_retos_screen.dart';
import 'package:traza/screens/admin/panel_admin_screen.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/niveles_falso.dart';

class _RetosVacio implements RetosRepository {
  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async =>
      const [];

  @override
  Future<Reto> crear(NuevoReto reto) async => throw UnimplementedError();
}

/// Pruebas del panel del administrador (SCRUM-194).
void main() {
  testWidgets('ofrece un acceso por cada área que administra', (tester) async {
    await _montar(tester);

    expect(find.text('Panel de administrador'), findsOneWidget);
    expect(find.byKey(PanelAdminScreen.claveRetos), findsOneWidget);
    expect(find.byKey(PanelAdminScreen.claveNiveles), findsOneWidget);
  });

  testWidgets('deja claro que la sesión es de administrador', (tester) async {
    await _montar(tester);

    expect(find.text('Administrador'), findsOneWidget);
  });

  testWidgets('desde la gestión de retos se vuelve al panel', (tester) async {
    await _montar(tester);

    await tester.tap(find.byKey(PanelAdminScreen.claveRetos));
    await tester.pumpAndSettle();
    expect(find.byType(GestionRetosScreen), findsOneWidget);
    // El distintivo no se repite dentro de la gestión.
    expect(find.text('Administrador'), findsNothing);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(PanelAdminScreen), findsOneWidget);
  });

  testWidgets('desde la gestión de niveles se vuelve al panel', (tester) async {
    await _montar(tester);

    await tester.tap(find.byKey(PanelAdminScreen.claveNiveles));
    await tester.pumpAndSettle();
    expect(find.byType(GestionNivelesScreen), findsOneWidget);
    expect(find.text('Administrador'), findsNothing);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(PanelAdminScreen), findsOneWidget);
  });

  testWidgets('la salida de la sesión está en el panel', (tester) async {
    await _montar(tester);

    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);
  });
}

/// Abre el panel con las dos gestiones reales colgando de él.
Future<void> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/inicio',
    routes: [
      GoRoute(path: '/inicio', builder: (_, _) => const PanelAdminScreen()),
      GoRoute(
        path: GestionRetosScreen.ruta,
        builder: (_, _) => const GestionRetosScreen(),
      ),
      GoRoute(
        path: GestionNivelesScreen.ruta,
        builder: (_, _) => const GestionNivelesScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        retosRepositoryProvider.overrideWithValue(_RetosVacio()),
        nivelesRepositoryProvider.overrideWithValue(NivelesFalso()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
