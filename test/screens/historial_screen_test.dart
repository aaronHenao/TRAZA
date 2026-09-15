import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/screens/history/historial_screen.dart';
import 'package:traza/services/historial_service.dart';
import 'package:traza/services/reloj_provider.dart';

/// Repositorio de mentira: responde lo que la prueba le indique.
class _RepositorioFalso implements HistorialRepository {
  _RepositorioFalso(this.respuesta);

  Future<List<ResumenEntrenamiento>> Function() respuesta;
  var consultas = 0;

  @override
  Future<List<ResumenEntrenamiento>> cargar() {
    consultas++;
    return respuesta();
  }
}

/// Pruebas del historial de entrenamientos (SCRUM-44).
void main() {
  final ahora = DateTime(2026, 9, 15, 9);

  final entrenamientos = [
    ResumenEntrenamiento(
      entrenamientoId: 'e2',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 15, 7),
      duracion: const Duration(minutes: 28, seconds: 14),
      distanciaMetros: 5100,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e1',
      nombreActividad: 'Caminar',
      fechaFin: DateTime(2026, 9, 10, 18),
      duracion: const Duration(minutes: 32, seconds: 5),
      distanciaMetros: 3200,
    ),
  ];

  Future<_RepositorioFalso> abrirHistorial(
    WidgetTester tester, {
    required Future<List<ResumenEntrenamiento>> Function() respuesta,
    bool esperar = true,
  }) async {
    final repositorio = _RepositorioFalso(respuesta);
    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(
          path: '/inicio',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/historial'),
              child: const Text('Pantalla Inicio'),
            ),
          ),
        ),
        GoRoute(
          path: '/historial',
          builder: (context, state) => const HistorialScreen(),
        ),
        GoRoute(
          path: '/resumen/:entrenamientoId',
          builder: (context, state) => Scaffold(
            body: Text('Resumen ${state.pathParameters['entrenamientoId']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Pantalla Inicio'));
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    return repositorio;
  }

  group('SCRUM-123 y SCRUM-126: lista', () {
    testWidgets('muestra cada entrenamiento con fecha, distancia y tiempo', (
      tester,
    ) async {
      await abrirHistorial(tester, respuesta: () async => entrenamientos);

      expect(find.text('Historial de entrenamientos'), findsOneWidget);
      expect(find.text('Correr · hoy'), findsOneWidget);
      expect(find.text('5.10 km · 00:28:14'), findsOneWidget);
      expect(find.text('Caminar · 10 sep'), findsOneWidget);
      expect(find.text('3.20 km · 00:32:05'), findsOneWidget);
    });

    testWidgets('sin entrenamientos muestra el estado vacío', (tester) async {
      await abrirHistorial(tester, respuesta: () async => []);

      expect(find.text('Aún no tienes entrenamientos'), findsOneWidget);
      await tester.tap(find.text('Iniciar mi primer entrenamiento'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Inicio'), findsOneWidget);
    });
  });

  group('SCRUM-127: carga y error', () {
    testWidgets('mientras consulta muestra el indicador de carga', (
      tester,
    ) async {
      final pendiente = Completer<List<ResumenEntrenamiento>>();
      await abrirHistorial(
        tester,
        respuesta: () => pendiente.future,
        esperar: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendiente.complete(entrenamientos);
      await tester.pumpAndSettle();
      expect(find.text('Correr · hoy'), findsOneWidget);
    });

    testWidgets('si falla, "Reintentar" vuelve a consultar', (tester) async {
      var falla = true;
      final repositorio = await abrirHistorial(
        tester,
        respuesta: () async {
          if (falla) throw Exception('sin red');
          return entrenamientos;
        },
      );

      expect(find.text('No pudimos cargar tu historial'), findsOneWidget);

      falla = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(repositorio.consultas, 2);
      expect(find.text('Correr · hoy'), findsOneWidget);
    });
  });

  group('SCRUM-125: navegación', () {
    testWidgets('tocar un entrenamiento abre su resumen', (tester) async {
      await abrirHistorial(tester, respuesta: () async => entrenamientos);

      await tester.tap(find.text('Caminar · 10 sep'));
      await tester.pumpAndSettle();

      expect(find.text('Resumen e1'), findsOneWidget);
    });

    testWidgets('avisa al resumen que viene del historial', (tester) async {
      await abrirHistorial(tester, respuesta: () async => entrenamientos);
      await tester.tap(find.text('Correr · hoy'));
      await tester.pumpAndSettle();

      final estado = GoRouterState.of(tester.element(find.text('Resumen e2')));
      expect(estado.uri.queryParameters['desde'], 'historial');

      GoRouter.of(tester.element(find.text('Resumen e2'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Historial de entrenamientos'), findsOneWidget);
    });

    testWidgets('la flecha de atrás vuelve a Inicio', (tester) async {
      await abrirHistorial(tester, respuesta: () async => entrenamientos);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Inicio'), findsOneWidget);
    });
  });
}
