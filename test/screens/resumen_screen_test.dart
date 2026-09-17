import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/screens/summary/resumen_screen.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/widgets/mapa_trayecto.dart';
import 'package:traza/widgets/trazado_recorrido.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';

/// Pruebas de la pantalla de resumen: su diseño (SCRUM-117), que muestre solo
/// la sesión que indica la navegación (SCRUM-122) y de dónde salen sus datos
/// (SCRUM-118).
void main() {
  final resumen = ResumenEntrenamiento(
    entrenamientoId: 'e-123',
    nombreActividad: 'Trote',
    fechaFin: DateTime(2026, 1, 1, 8, 32, 17),
    duracion: const Duration(minutes: 32, seconds: 17),
    distanciaMetros: 5230.5,
  );

  /// El mismo entrenamiento tal como quedó guardado en Supabase.
  final guardado = ResumenEntrenamiento(
    entrenamientoId: 'e-123',
    nombreActividad: 'Caminar',
    fechaFin: DateTime(2026, 1, 1, 8, 45),
    duracion: const Duration(minutes: 45),
    distanciaMetros: 3200,
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

    testWidgets('sin puntos GPS el recuadro dice que no hay recorrido', (
      tester,
    ) async {
      await _montar(tester, resumen: resumen);

      expect(find.text('Sin recorrido registrado'), findsOneWidget);
      expect(find.byType(TrazadoRecorrido), findsNothing);
    });

    testWidgets('con puntos GPS dibuja el trazado del recorrido '
        '(SCRUM-119)', (tester) async {
      await _montar(
        tester,
        resumen: ResumenEntrenamiento(
          entrenamientoId: 'e-123',
          nombreActividad: 'Trote',
          fechaFin: DateTime(2026, 1, 1, 8, 32, 17),
          duracion: const Duration(minutes: 32, seconds: 17),
          distanciaMetros: 5230.5,
          puntos: [
            puntoDePrueba(latitud: 6.2311, longitud: -75.6105),
            puntoDePrueba(latitud: 6.2320, longitud: -75.6100),
            puntoDePrueba(latitud: 6.2332, longitud: -75.6108),
          ],
        ),
      );

      final dibujo = tester.widget<TrazadoRecorrido>(
        find.byType(TrazadoRecorrido),
      );
      expect(dibujo.trazado.puntos, hasLength(3));
      expect(find.text('Sin recorrido registrado'), findsNothing);
    });

    testWidgets('al tocar el recorrido lo muestra sobre el mapa y se puede '
        'volver al resumen (SCRUM-120)', (tester) async {
      final puntos = [
        puntoDePrueba(latitud: 6.2311, longitud: -75.6105),
        puntoDePrueba(latitud: 6.2320, longitud: -75.6100),
        puntoDePrueba(latitud: 6.2332, longitud: -75.6108),
      ];
      await _montar(
        tester,
        resumen: ResumenEntrenamiento(
          entrenamientoId: 'e-123',
          nombreActividad: 'Trote',
          fechaFin: DateTime(2026, 1, 1, 8, 32, 17),
          duracion: const Duration(minutes: 32, seconds: 17),
          distanciaMetros: 5230.5,
          puntos: puntos,
        ),
      );
      expect(find.byType(MapaTrayecto), findsNothing);

      await tester.tap(find.text('Ver en el mapa'));
      await tester.pumpAndSettle();

      final mapa = tester.widget<MapaTrayecto>(find.byType(MapaTrayecto));
      expect(mapa.puntos, puntos);
      expect(find.text('Recorrido'), findsOneWidget);
      expect(find.text('Partida'), findsOneWidget);
      expect(find.text('Llegada'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar mapa'));
      await tester.pumpAndSettle();

      expect(find.byType(MapaTrayecto), findsNothing);
      expect(find.text('¡Entrenamiento completado!'), findsOneWidget);
    });

    testWidgets('sin puntos GPS no ofrece ver el mapa', (tester) async {
      await _montar(tester, resumen: resumen);

      expect(find.text('Ver en el mapa'), findsNothing);
    });

    testWidgets('la X de la barra superior vuelve al inicio', (tester) async {
      await _montar(tester, resumen: resumen);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla de inicio'), findsOneWidget);
    });

    testWidgets('abierto desde el historial, la X vuelve al historial '
        '(SCRUM-125)', (tester) async {
      await _montar(tester, resumen: null, guardados: {'e-123': resumen});
      final router = GoRouter.of(tester.element(find.byType(ResumenScreen)));
      router.go('/historial');
      await tester.pumpAndSettle();
      router.push('/resumen/e-123?desde=historial');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla de historial'), findsOneWidget);
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
      await _montar(tester, ruta: '/resumen', resumen: null);

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

    testWidgets('con los datos de otro entrenamiento no los muestra: busca el '
        'de la ruta', (tester) async {
      final entrenamientos = await _montar(
        tester,
        ruta: '/resumen/e-999',
        resumen: resumen,
      );

      expect(entrenamientos.consultas, ['e-999']);
      _esperarEstadoVacio();
      expect(find.text('00:32:17'), findsNothing);
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
      final entrenamientos = await _montar(
        tester,
        ruta: '/resumen',
        resumen: resumen,
      );

      _esperarEstadoVacio();
      // Sin id en la ruta no hay nada que buscar.
      expect(entrenamientos.consultas, isEmpty);
    });
  });

  group('datos de la sesión finalizada (SCRUM-118)', () {
    testWidgets('con los datos de la navegación no consulta Supabase', (
      tester,
    ) async {
      final entrenamientos = await _montar(tester, resumen: resumen);

      expect(entrenamientos.consultas, isEmpty);
      expect(find.text('Trote · hoy'), findsOneWidget);
    });

    testWidgets('sin los datos de la navegación, lee de Supabase el '
        'entrenamiento de la ruta', (tester) async {
      // Por ejemplo, al recargar la página en la web.
      final entrenamientos = await _montar(
        tester,
        ruta: '/resumen/e-123',
        resumen: null,
        guardados: {'e-123': guardado},
      );

      expect(entrenamientos.consultas, ['e-123']);
      expect(find.text('Caminar · hoy'), findsOneWidget);
      expect(find.text('00:45:00'), findsOneWidget);
      expect(find.text('3.20 km'), findsOneWidget);
    });

    testWidgets('mientras lee muestra que está cargando', (tester) async {
      final espera = Completer<void>();
      await _montar(
        tester,
        ruta: '/resumen/e-123',
        resumen: null,
        guardados: {'e-123': guardado},
        espera: espera,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Caminar · hoy'), findsNothing);

      espera.complete();
      await tester.pumpAndSettle();

      expect(find.text('Caminar · hoy'), findsOneWidget);
    });

    testWidgets('si el entrenamiento no está finalizado, no existe o no es del '
        'usuario, muestra el estado vacío', (tester) async {
      // El repositorio real devuelve null en los tres casos.
      await _montar(tester, ruta: '/resumen/e-123', resumen: null);

      _esperarEstadoVacio();
    });

    testWidgets('si falla la lectura lo avisa y permite reintentar', (
      tester,
    ) async {
      final entrenamientos = await _montar(
        tester,
        ruta: '/resumen/e-123',
        resumen: null,
        guardados: {'e-123': guardado},
        error: StateError('Supabase no disponible'),
      );

      expect(find.text('No pudimos cargar el resumen'), findsOneWidget);

      // Vuelve la conexión.
      entrenamientos.error = null;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(entrenamientos.consultas, ['e-123', 'e-123']);
      expect(find.text('Caminar · hoy'), findsOneWidget);
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

/// Entrenamientos guardados en memoria: anota cada lectura y, si la prueba lo
/// indica, espera o falla.
class _EntrenamientosFalso implements EntrenamientoRepository {
  _EntrenamientosFalso({required this.guardados, this.error, this.espera});

  final Map<String, ResumenEntrenamiento> guardados;
  final consultas = <String>[];

  /// Si no es null, `cargarFinalizado` lo lanza.
  Object? error;

  /// Si no es null, `cargarFinalizado` no responde hasta que se complete.
  final Completer<void>? espera;

  @override
  Future<String> crear({required String tipoActividadId}) =>
      throw UnimplementedError('El resumen no crea entrenamientos');

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) => throw UnimplementedError('El resumen no descarta entrenamientos');

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) async {
    consultas.add(entrenamientoId);
    await espera?.future;
    final error = this.error;
    if (error != null) throw error;
    return guardados[entrenamientoId];
  }

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) => throw UnimplementedError('El resumen no cierra entrenamientos');
}

/// Abre [ruta] con [resumen] como datos de la navegación, en un teléfono de
/// 390 x 844, con el inicio como destino al cerrar y el reloj fijo el mismo día
/// del entrenamiento. Las rutas del resumen son las mismas de `main.dart`.
///
/// Devuelve el repositorio falso para revisar qué se consultó.
Future<_EntrenamientosFalso> _montar(
  WidgetTester tester, {
  required ResumenEntrenamiento? resumen,
  String ruta = '/resumen/e-123',
  Map<String, ResumenEntrenamiento> guardados = const {},
  Object? error,
  Completer<void>? espera,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final entrenamientos = _EntrenamientosFalso(
    guardados: guardados,
    error: error,
    espera: espera,
  );

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
      GoRoute(
        path: '/historial',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de historial')),
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
        entrenamientoRepositoryProvider.overrideWithValue(entrenamientos),
        // El mapa del recorrido no descarga tiles reales.
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // Con una lectura pendiente el indicador de carga no deja de animarse, así
  // que no se espera a que la pantalla quede quieta.
  if (espera == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }

  return entrenamientos;
}
