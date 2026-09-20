import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/theme/traza_theme.dart';
import 'package:traza/widgets/mapa_recorrido.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';

void main() {
  late FuenteUbicacionFalsa fuente;
  late ProveedorTilesFalso tiles;

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    tiles = ProveedorTilesFalso();
    addTearDown(() => fuente.cerrar());
  });

  late ProviderContainer container;

  Future<void> montar(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        fuenteUbicacionProvider.overrideWithValue(fuente),
        proveedorTilesProvider.overrideWithValue(tiles),
        relojProvider.overrideWithValue(RelojFalso().call),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 375, height: 500, child: MapaRecorrido()),
          ),
        ),
      ),
    );
  }

  Future<void> emitir(WidgetTester tester, PuntoGps punto) async {
    fuente.emitir(punto);
    await tester.pump();
    await tester.pump();
  }

  /// Los puntos solo se registran con el cronómetro en curso.
  void iniciarActividad() =>
      container.read(cronometroProvider.notifier).iniciar();

  void pausarActividad() =>
      container.read(cronometroProvider.notifier).pausar();

  void detenerActividad() =>
      container.read(cronometroProvider.notifier).detener();

  List<LatLng> trazo(WidgetTester tester) {
    final capas = find.byType(PolylineLayer);
    if (capas.evaluate().isEmpty) return const [];
    return tester.widget<PolylineLayer>(capas).polylines.single.points;
  }

  MapController controlador(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  LatLng marcador(WidgetTester tester) => tester
      .widget<MarkerLayer>(find.byType(MarkerLayer))
      .markers
      .single
      .point;

  testWidgets('no dibuja el mapa hasta tener la primera posición',
      (tester) async {
    await montar(tester);

    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('con la primera posición centra el mapa y pone el marcador ahí',
      (tester) async {
    await montar(tester);

    await emitir(tester, puntoDePrueba(latitud: 6.2311, longitud: -75.6105));

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(MapaRecorrido.claveMarcador), findsOneWidget);
    expect(marcador(tester), const LatLng(6.2311, -75.6105));
    expect(
      controlador(tester).camera.center,
      const LatLng(6.2311, -75.6105),
    );
    expect(controlador(tester).camera.zoom, MapaRecorrido.zoomInicial);
  });

  testWidgets('conforme avanza mueve el marcador y sigue con la cámara',
      (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba(latitud: 6.2311, longitud: -75.6105));

    await emitir(tester, puntoDePrueba(latitud: 6.2350, longitud: -75.6140));

    expect(marcador(tester), const LatLng(6.2350, -75.6140));
    expect(
      controlador(tester).camera.center,
      const LatLng(6.2350, -75.6140),
    );
  });

  testWidgets('al seguir al usuario conserva el zoom actual', (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    controlador(tester).move(controlador(tester).camera.center, 15);
    await tester.pump();
    await emitir(tester, puntoDePrueba(latitud: 6.2350, longitud: -75.6140));

    expect(controlador(tester).camera.zoom, 15);
  });

  testWidgets('con un solo punto todavía no hay trazo', (tester) async {
    await montar(tester);
    iniciarActividad();

    await emitir(tester, puntoDePrueba(latitud: 6.2311, longitud: -75.6105));

    expect(find.byType(PolylineLayer), findsNothing);
    detenerActividad();
  });

  testWidgets('conforme avanza deja el trazo del recorrido detrás',
      (tester) async {
    await montar(tester);
    iniciarActividad();
    await emitir(tester, puntoDePrueba(latitud: 6.2311, longitud: -75.6105));

    await emitir(tester, puntoDePrueba(latitud: 6.2320, longitud: -75.6120));
    await emitir(tester, puntoDePrueba(latitud: 6.2350, longitud: -75.6140));

    expect(trazo(tester), const [
      LatLng(6.2311, -75.6105),
      LatLng(6.2320, -75.6120),
      LatLng(6.2350, -75.6140),
    ]);
    expect(marcador(tester), const LatLng(6.2350, -75.6140));
    detenerActividad();
  });

  testWidgets('el trazo se dibuja con el color y grosor del prototipo',
      (tester) async {
    await montar(tester);
    iniciarActividad();
    await emitir(tester, puntoDePrueba(latitud: 6.2311, longitud: -75.6105));
    await emitir(tester, puntoDePrueba(latitud: 6.2350, longitud: -75.6140));

    final linea = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single;
    expect(linea.color, TrazaColors.accent);
    expect(linea.strokeWidth, MapaRecorrido.grosorTrazo);
    detenerActividad();
  });

  testWidgets('en pausa el marcador sigue al usuario pero el trazo no crece',
      (tester) async {
    await montar(tester);
    iniciarActividad();
    await emitir(tester, puntoDePrueba(latitud: 6.2311, longitud: -75.6105));
    await emitir(tester, puntoDePrueba(latitud: 6.2320, longitud: -75.6120));

    pausarActividad();
    await emitir(tester, puntoDePrueba(latitud: 6.2350, longitud: -75.6140));

    expect(marcador(tester), const LatLng(6.2350, -75.6140));
    expect(trazo(tester), const [
      LatLng(6.2311, -75.6105),
      LatLng(6.2320, -75.6120),
    ]);
    detenerActividad();
  });

  testWidgets('usa los tiles de CARTO identificando la app',
      (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    final capa = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(capa.urlTemplate, urlTiles);
    expect(capa.tileProvider.headers['User-Agent'], contains(paqueteUserAgent));
    expect(tiles.tilesPedidos, greaterThan(0));
  });

  testWidgets('muestra la atribución de OpenStreetMap y CARTO', (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    expect(find.text(atribucionMapa), findsOneWidget);
  });
}
