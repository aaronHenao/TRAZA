import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/screens/summary/resumen_screen.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/reloj_falso.dart';

/// Pruebas de la pantalla de resumen: su diseño (SCRUM-117) y que muestre
/// solo la sesión que indica la navegación (SCRUM-122).
void main() {
  final resumen = ResumenEntrenamiento(
    entrenamientoId: 'e-123',
    nombreActividad: 'Trote',
    fechaFin: DateTime(2026, 1, 1, 8, 32, 17),
    duracion: const Duration(minutes: 32, seconds: 17),
    distanciaMetros: 5230.5,
  );

  group('diseño (SCRUM-117)', () {
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
          entrenamientoId: 'e-123',
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

    testWidgets('el estado vacío también permite volver al inicio', (
      tester,
    ) async {
      await _montar(tester, resumen: null);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Volver al inicio'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla de inicio'), findsOneWidget);
    });
  });

  group('solo la sesión recién finalizada (SCRUM-122)', () {
    testWidgets('muestra el resumen cuando es el del entrenamiento de la '
        'ruta', (tester) async {
      await _montar(tester, ruta: '/resumen/e-123', resumen: resumen);

      expect(find.text('¡Entrenamiento completado!'), findsOneWidget);
      expect(find.text('00:32:17'), findsOneWidget);
    });

    testWidgets('con los datos de otro entrenamiento no muestra nada', (
      tester,
    ) async {
      await _montar(tester, ruta: '/resumen/e-999', resumen: resumen);

      _esperarEstadoVacio();
      expect(find.text('00:32:17'), findsNothing);
    });

    testWidgets('sin los datos, aunque la ruta tenga el id, no busca otro '
        'resumen', (tester) async {
      // Por ejemplo, al recargar la página en la web o abrir la ruta a mano.
      await _montar(tester, ruta: '/resumen/e-123', resumen: null);

      _esperarEstadoVacio();
    });

    testWidgets('sin sesión muestra el resumen de la sesión local en '
        '/resumen', (tester) async {
      await _montar(
        tester,
        ruta: '/resumen',
        resumen: ResumenEntrenamiento(
          entrenamientoId: null,
          nombreActividad: 'Correr',
          fechaFin: DateTime(2026, 1, 1, 8, 5),
          duracion: const Duration(minutes: 5),
        ),
      );

      expect(find.text('¡Entrenamiento completado!'), findsOneWidget);
      expect(find.text('00:05:00'), findsOneWidget);
    });

    testWidgets('un resumen con id no se muestra en la ruta sin id', (
      tester,
    ) async {
      await _montar(tester, ruta: '/resumen', resumen: resumen);

      _esperarEstadoVacio();
    });
  });

  group('ruta del resumen', () {
    test('lleva el id del entrenamiento', () {
      expect(ResumenScreen.rutaPara('e-123'), '/resumen/e-123');
    });

    test('sin sesión es /resumen a secas', () {
      expect(ResumenScreen.rutaPara(null), '/resumen');
    });
  });
}

void _esperarEstadoVacio() {
  expect(find.text('No hay un entrenamiento para mostrar'), findsOneWidget);
  expect(find.text('¡Entrenamiento completado!'), findsNothing);
}

/// Abre [ruta] con [resumen] como datos de la navegación, en un teléfono de
/// 390 x 844, con el inicio como destino al cerrar y el reloj fijo el mismo día
/// del entrenamiento. Las rutas del resumen son las mismas de `main.dart`.
Future<void> _montar(
  WidgetTester tester, {
  required ResumenEntrenamiento? resumen,
  String ruta = '/resumen/e-123',
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: ruta,
    initialExtra: resumen,
    routes: [
      GoRoute(
        path: '/resumen',
        builder: (_, estado) => ResumenScreen.desdeRuta(estado),
        routes: [
          GoRoute(
            path: ':entrenamientoId',
            builder: (_, estado) => ResumenScreen.desdeRuta(estado),
          ),
        ],
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
