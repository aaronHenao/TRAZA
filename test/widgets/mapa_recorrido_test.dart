import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/mapa_recorrido.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  late FuenteUbicacionFalsa fuente;
  late ProveedorTilesFalso tiles;

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    tiles = ProveedorTilesFalso();
    addTearDown(() => fuente.cerrar());
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fuenteUbicacionProvider.overrideWithValue(fuente),
          proveedorTilesProvider.overrideWithValue(tiles),
        ],
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

  testWidgets('usa los tiles de OpenStreetMap identificando la app',
      (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    final capa = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(capa.urlTemplate, urlTilesOsm);
    expect(capa.tileProvider.headers['User-Agent'], contains(paqueteUserAgent));
    expect(tiles.tilesPedidos, greaterThan(0));
  });

  testWidgets('muestra la atribución de OpenStreetMap', (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    expect(find.text(atribucionOsm), findsOneWidget);
  });
}
