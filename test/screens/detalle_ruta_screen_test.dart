import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/mapa_trayecto.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas del detalle de una ruta (SCRUM-240): que diga cuánto mide sin que
/// haya que empezar nada, y que lo diga también cuando no lo sabe.
void main() {
  Ruta ruta({
    double? distanciaKm = 5.23,
    String? descripcion,
    List<PuntoRuta> trazado = const [
      PuntoRuta(latitud: 6.2442, longitud: -75.5812),
      PuntoRuta(latitud: 6.2450, longitud: -75.5800),
    ],
  }) => Ruta(
    id: 'ruta-1',
    autorId: 'usuario-9',
    autorNombre: 'Ana',
    nombre: 'Vuelta al Parque Norte',
    descripcion: descripcion,
    estado: EstadoRuta.publicada,
    distanciaKm: distanciaKm,
    trazado: trazado,
    fechaCreacion: DateTime(2026, 10, 16),
    fechaPublicacion: DateTime(2026, 10, 17, 9),
  );

  group('lo que muestra', () {
    testWidgets('el nombre, de quien es, y cuanto mide (criterios 1 y 2)', (
      tester,
    ) async {
      await _abrir(tester, rutas: [ruta(descripcion: 'Plana y con sombra.')]);

      expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
      expect(find.text('Por Ana · Hoy'), findsOneWidget);

      // La distancia, con su unidad.
      expect(find.text('5.23 km'), findsOneWidget);
      expect(find.text('Distancia total de la ruta'), findsOneWidget);

      expect(find.text('Plana y con sombra.'), findsOneWidget);

      // Criterio 2: no hay nada que iniciar para verla.
      expect(find.widgetWithText(FilledButton, 'Iniciar ruta'), findsNothing);
    });

    testWidgets('el trazado sobre el mapa', (tester) async {
      await _abrir(tester, rutas: [ruta()]);

      expect(find.byType(MapaTrayecto), findsOneWidget);
    });

    testWidgets('una ruta sin trazado no revienta el mapa', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: const [])]);

      expect(find.byType(MapaTrayecto), findsNothing);
      expect(find.text('Esta ruta no guardó su trazado'), findsOneWidget);
    });
  });

  group('sin distancia registrada (criterio 4)', () {
    testWidgets('lo dice en vez de callarselo o inventarlo', (tester) async {
      await _abrir(tester, rutas: [ruta(distanciaKm: null)]);

      expect(find.text('Distancia no disponible'), findsOneWidget);
      expect(
        find.textContaining('no podemos decirte cuánto mide'),
        findsOneWidget,
      );
      // Y no aparece ningún número inventado.
      expect(find.textContaining(' km'), findsNothing);
    });
  });

  group('cuando no se puede abrir', () {
    testWidgets('una ruta que ya no esta lo explica', (tester) async {
      await _abrir(tester, rutas: const []);

      expect(find.text('Esta ruta ya no está disponible'), findsOneWidget);
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsNothing);
    });

    testWidgets('si falla la lectura deja reintentar', (tester) async {
      final repositorio = await _abrir(
        tester,
        rutas: [ruta()],
        error: StateError('sin red'),
      );

      expect(find.text('No pudimos cargar la ruta'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.byKey(DetalleRutaScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text('5.23 km'), findsOneWidget);
    });
  });
}

Future<RutasRepositorioFalso> _abrir(
  WidgetTester tester, {
  required List<Ruta> rutas,
  Object? error,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = RutasRepositorioFalso(rutas: rutas, error: error);

  final router = GoRouter(
    initialLocation: DetalleRutaScreen.rutaDe('ruta-1'),
    routes: [
      GoRoute(
        path: DetalleRutaScreen.ruta,
        builder: (_, estado) =>
            DetalleRutaScreen(rutaId: estado.pathParameters['rutaId']!),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rutasRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 12)),
        // El mapa no descarga tiles reales.
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return repositorio;
}
