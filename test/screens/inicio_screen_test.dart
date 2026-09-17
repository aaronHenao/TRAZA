import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/screens/home/inicio_screen.dart';
import 'package:traza/services/historial_service.dart';
import 'package:traza/services/inicio_provider.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/widgets/navegacion_principal.dart';

/// Historial de mentira: responde lo que la prueba le indique.
class _HistorialFalso implements HistorialRepository {
  _HistorialFalso(this.respuesta);

  Future<List<ResumenEntrenamiento>> Function() respuesta;

  @override
  Future<List<ResumenEntrenamiento>> cargar() => respuesta();
}

/// Objetivos de mentira: solo se le pregunta por la meta de distancia.
class _ObjetivosFalsos implements ObjetivosRepository {
  _ObjetivosFalsos(this.respuesta);

  Future<Map<TipoObjetivo, num>> Function() respuesta;

  @override
  Future<Map<TipoObjetivo, num>> cargar() => respuesta();

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {}
}

/// Pruebas de la portada: el saludo, el avance de la semana contra el
/// objetivo del perfil, los últimos entrenamientos y las salidas hacia
/// actividad, historial y perfil.
void main() {
  final ahora = DateTime(2026, 9, 16, 10);

  final entrenamientos = [
    ResumenEntrenamiento(
      entrenamientoId: 'e3',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 16, 7),
      duracion: const Duration(minutes: 28, seconds: 14),
      distanciaMetros: 5100,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e2',
      nombreActividad: 'Trote',
      fechaFin: DateTime(2026, 9, 15, 7),
      duracion: const Duration(minutes: 20),
      distanciaMetros: 3000,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e1',
      nombreActividad: 'Caminar',
      fechaFin: DateTime(2026, 9, 14, 18),
      duracion: const Duration(minutes: 32, seconds: 5),
      distanciaMetros: 2000,
    ),
    // Semana anterior: no entra en el avance ni cabe en los últimos.
    ResumenEntrenamiento(
      entrenamientoId: 'e0',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 11, 18),
      duracion: const Duration(minutes: 15),
      distanciaMetros: 9000,
    ),
  ];

  Future<void> abrirPortada(
    WidgetTester tester, {
    Future<List<ResumenEntrenamiento>> Function()? historial,
    Future<Map<TipoObjetivo, num>> Function()? objetivos,
    String? nombre = 'Ana',
    bool esperar = true,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const InicioScreen()),
        GoRoute(
          path: '/actividad',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Actividad')),
        ),
        GoRoute(
          path: '/historial',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Historial')),
        ),
        GoRoute(
          path: '/perfil',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Perfil')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialRepositoryProvider.overrideWithValue(
            _HistorialFalso(historial ?? () async => entrenamientos),
          ),
          objetivosRepositoryProvider.overrideWithValue(
            _ObjetivosFalsos(
              objetivos ?? () async => {TipoObjetivo.distancia: 15},
            ),
          ),
          // El nombre sale de la sesión de Supabase, que en las pruebas no
          // existe.
          nombreUsuarioProvider.overrideWithValue(nombre),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('saludo', () {
    testWidgets('saluda con el nombre de la persona', (tester) async {
      await abrirPortada(tester);

      expect(find.text('Hola, Ana'), findsOneWidget);
      expect(find.text('Vamos por tu meta semanal'), findsOneWidget);
    });

    testWidgets('sin nombre saluda igual, sin dejar el hueco', (tester) async {
      await abrirPortada(tester, nombre: null);

      expect(find.text('Hola'), findsOneWidget);
    });
  });

  group('avance de la semana', () {
    testWidgets('muestra lo recorrido contra la meta del perfil', (
      tester,
    ) async {
      await abrirPortada(tester);

      expect(find.text('ESTA SEMANA'), findsOneWidget);
      // 5.1 + 3.0 + 2.0 km desde el lunes; el de la semana pasada no entra.
      expect(find.text('10.1 / 15 km'), findsOneWidget);
      expect(find.text('3 entrenamientos'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('sin meta de distancia invita a ponerse una', (tester) async {
      await abrirPortada(tester, objetivos: () async => {});

      expect(find.text('10.1 km'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.text(
          'Ponte una meta de distancia en tu perfil para seguirla desde aquí.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('si los objetivos fallan el avance se muestra igual', (
      tester,
    ) async {
      await abrirPortada(tester, objetivos: () async => throw Exception('x'));

      expect(find.text('10.1 km'), findsOneWidget);
      expect(
        find.text('No pudimos cargar tu progreso de esta semana.'),
        findsNothing,
      );
    });

    testWidgets('con un solo entrenamiento el conteo va en singular', (
      tester,
    ) async {
      await abrirPortada(tester, historial: () async => [entrenamientos.first]);

      expect(find.text('1 entrenamiento'), findsOneWidget);
    });

    testWidgets('mientras carga lo dice, y si falla también', (tester) async {
      final pendiente = Completer<List<ResumenEntrenamiento>>();
      await abrirPortada(
        tester,
        historial: () => pendiente.future,
        esperar: false,
      );

      expect(find.text('Cargando tu progreso…'), findsOneWidget);

      pendiente.completeError(Exception('sin red'));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar tu progreso de esta semana.'),
        findsOneWidget,
      );
      expect(find.text('No pudimos cargar tus entrenamientos.'), findsOneWidget);
    });
  });


  group('últimos entrenamientos', () {
    testWidgets('asoma los tres más recientes', (tester) async {
      await abrirPortada(tester);

      expect(find.text('ÚLTIMOS ENTRENAMIENTOS'), findsOneWidget);
      expect(find.text('Correr · hoy'), findsOneWidget);
      expect(find.text('5.10 km · 00:28:14'), findsOneWidget);
      expect(find.text('Trote · ayer'), findsOneWidget);
      expect(find.text('Caminar · 14 sep'), findsOneWidget);
      // El cuarto es de la semana pasada: para verlo está "Ver todos".
      expect(find.text('Correr · 11 sep'), findsNothing);
    });

    testWidgets('sin entrenamientos invita a empezar y no ofrece el '
        'historial', (tester) async {
      await abrirPortada(tester, historial: () async => []);

      expect(
        find.text('Todavía no has entrenado. Toca el botón + para empezar.'),
        findsOneWidget,
      );
      expect(find.text('Ver todos'), findsNothing);
    });

    testWidgets('"Ver todos" abre el historial completo', (tester) async {
      await abrirPortada(tester);

      await tester.tap(find.text('Ver todos'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Historial'), findsOneWidget);
    });
  });

  group('salidas de la portada', () {
    testWidgets('el "+" lleva a elegir la actividad', (tester) async {
      await abrirPortada(tester);

      await tester.tap(find.byKey(NavegacionPrincipal.claveBoton));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Actividad'), findsOneWidget);
    });

    testWidgets('la barra lleva al perfil', (tester) async {
      await abrirPortada(tester);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Perfil'), findsOneWidget);
    });

    testWidgets('la barra lleva al historial', (tester) async {
      await abrirPortada(tester);

      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Historial'), findsOneWidget);
    });
  });
}
