import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/screens/admin/formulario_nivel_screen.dart';
import 'package:traza/screens/admin/gestion_niveles_screen.dart';
import 'package:traza/services/niveles_service.dart';

import '../utiles/niveles_falso.dart';

/// Pruebas de la pantalla de gestión de niveles (SCRUM-182).
void main() {
  const niveles = [
    Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
    Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500),
    Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500),
  ];

  testWidgets('muestra los niveles del umbral más bajo al más alto', (
    tester,
  ) async {
    await _montar(tester, NivelesFalso(catalogo: niveles));

    final tarjetas = tester
        .widgetList<TarjetaNivel>(find.byType(TarjetaNivel))
        .toList();
    expect(tarjetas.map((tarjeta) => tarjeta.nivel.nombre), [
      'Bronce',
      'Plata',
      'Oro',
    ]);
    // La posición en la progresión, para que se vea el orden de un vistazo.
    expect(tarjetas.map((tarjeta) => tarjeta.posicion), [1, 2, 3]);
  });

  testWidgets('cada nivel dice con cuánta experiencia se entra y hasta dónde '
      'llega', (tester) async {
    await _montar(tester, NivelesFalso(catalogo: niveles));

    expect(find.text('100 XP'), findsOneWidget);
    // Bronce llega justo hasta donde empieza Plata.
    expect(find.text('Hasta 499 XP'), findsOneWidget);
    expect(find.text('Hasta 1499 XP'), findsOneWidget);
    // El último no tiene final.
    expect(find.text('Nivel más alto'), findsOneWidget);
  });

  testWidgets('sin niveles invita a crear el primero', (tester) async {
    await _montar(tester, NivelesFalso());

    expect(find.text('Aún no hay niveles'), findsOneWidget);
    expect(find.byType(TarjetaNivel), findsNothing);
  });

  testWidgets('si la carga falla, avisa y permite reintentar', (tester) async {
    final repositorio = NivelesFalso(catalogo: niveles)
      ..errorAlListar = StateError('sin conexión');
    await _montar(tester, repositorio);

    expect(find.text('No pudimos cargar los niveles'), findsOneWidget);

    // Vuelve la conexión.
    repositorio.errorAlListar = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(find.byType(TarjetaNivel), findsNWidgets(3));
  });

  testWidgets('el botón + abre el formulario de nuevo nivel', (tester) async {
    await _montar(tester, NivelesFalso(catalogo: niveles));

    await tester.tap(find.byKey(GestionNivelesScreen.claveBotonNuevo));
    await tester.pumpAndSettle();

    expect(find.byType(FormularioNivelScreen), findsOneWidget);
    expect(find.text('Nuevo nivel'), findsOneWidget);
  });
}

/// Abre la gestión de niveles con [repositorio] como origen de los datos.
Future<void> _montar(WidgetTester tester, NivelesFalso repositorio) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: GestionNivelesScreen.ruta,
    routes: [
      GoRoute(
        path: GestionNivelesScreen.ruta,
        builder: (_, _) => const GestionNivelesScreen(),
        routes: [
          GoRoute(
            path: 'nuevo',
            builder: (_, _) => const FormularioNivelScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [nivelesRepositoryProvider.overrideWithValue(repositorio)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
