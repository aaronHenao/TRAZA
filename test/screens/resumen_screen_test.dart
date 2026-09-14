import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/screens/summary/resumen_screen.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/reloj_falso.dart';

/// Pruebas de la pantalla de resumen (SCRUM-117).
void main() {
  final resumen = ResumenEntrenamiento(
    nombreActividad: 'Trote',
    fechaFin: DateTime(2026, 1, 1, 8, 32, 17),
    duracion: const Duration(minutes: 32, seconds: 17),
    distanciaMetros: 5230.5,
  );

  testWidgets('muestra el título, la actividad con la fecha, el tiempo, la '
      'distancia y el ritmo', (tester) async {
    await _montar(tester, resumen: resumen);

    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('¡Entrenamiento completado!'), findsOneWidget);
    expect(find.text('Trote · hoy'), findsOneWidget);
    expect(find.text('00:32:17'), findsOneWidget);
    expect(find.text('Tiempo'), findsOneWidget);
    expect(find.text('5.23 km'), findsOneWidget);
    expect(find.text('Distancia'), findsOneWidget);
    expect(find.text('Ritmo promedio: 6\'10"/km'), findsOneWidget);
  });

  testWidgets('sin distancia calculada no inventa datos', (tester) async {
    await _montar(
      tester,
      resumen: ResumenEntrenamiento(
        nombreActividad: 'Correr',
        fechaFin: DateTime(2026, 1, 1, 8, 5),
        duracion: const Duration(minutes: 5),
      ),
    );

    expect(find.text(ResumenEntrenamiento.sinDato), findsOneWidget);
    expect(
      find.text('Ritmo promedio: ${ResumenEntrenamiento.sinDato}'),
      findsOneWidget,
    );
  });

  testWidgets('tiene el recuadro del recorrido', (tester) async {
    await _montar(tester, resumen: resumen);

    expect(find.text('Recorrido no disponible'), findsOneWidget);
  });

  testWidgets('la X de la barra superior vuelve al inicio', (tester) async {
    await _montar(tester, resumen: resumen);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de inicio'), findsOneWidget);
  });

  testWidgets('el botón principal vuelve al inicio', (tester) async {
    await _montar(tester, resumen: resumen);

    await tester.tap(find.widgetWithText(FilledButton, 'Volver al inicio'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de inicio'), findsOneWidget);
  });

  testWidgets('sin un entrenamiento muestra el estado vacío', (tester) async {
    await _montar(tester, resumen: null);

    expect(find.text('No hay un entrenamiento para mostrar'), findsOneWidget);
    expect(find.text('¡Entrenamiento completado!'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Volver al inicio'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de inicio'), findsOneWidget);
  });
}

/// Abre el resumen en un teléfono de 390 x 844, con el inicio como destino al
/// cerrar y el reloj fijo el mismo día del entrenamiento.
Future<void> _montar(
  WidgetTester tester, {
  required ResumenEntrenamiento? resumen,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/resumen',
    routes: [
      GoRoute(
        path: '/resumen',
        builder: (_, _) => ResumenScreen(resumen: resumen),
      ),
      GoRoute(
        path: '/inicio',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de inicio')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        relojProvider.overrideWithValue(
          RelojFalso(DateTime(2026, 1, 1, 9)).call,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
