import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/theme/app_colors.dart';
import 'package:traza/widgets/mapa_trayecto.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

/// Pruebas del mapa con el trayecto completo del resumen (SCRUM-120).
///
/// Los tiles salen de un proveedor falso, así que ninguna prueba toca la red.
void main() {
  /// Un recorrido corto por el campus de la Universidad de Medellín.
  final recorrido = [
    puntoDePrueba(latitud: 6.2311, longitud: -75.6105),
    puntoDePrueba(latitud: 6.2320, longitud: -75.6100),
    puntoDePrueba(latitud: 6.2332, longitud: -75.6108),
    puntoDePrueba(latitud: 6.2340, longitud: -75.6121),
  ];

  List<LatLng> coordenadas(List<PuntoGps> puntos) => [
    for (final punto in puntos) LatLng(punto.latitud, punto.longitud),
  ];

  Future<ProveedorTilesFalso> montar(
    WidgetTester tester,
    List<PuntoGps> puntos,
  ) async {
    final tiles = ProveedorTilesFalso();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [proveedorTilesProvider.overrideWithValue(tiles)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 375,
              height: 600,
              child: MapaTrayecto(puntos: puntos),
            ),
          ),
        ),
      ),
    );
    // El encuadre inicial se aplica cuando el mapa ya conoce su tamaño.
    await tester.pump();
    return tiles;
  }

  MapCamera camara(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byKey(MapaTrayecto.claveLlegada)));

  testWidgets('dibuja la línea del trayecto con todos los puntos, en orden', (
    tester,
  ) async {
    await montar(tester, recorrido);

    final linea = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single;
    expect(linea.points, coordenadas(recorrido));
    expect(linea.color, AppColors.accent);
    expect(linea.strokeWidth, MapaTrayecto.grosorLinea);
  });

  testWidgets('marca la partida en el primer punto y la llegada en el '
      'último', (tester) async {
    await montar(tester, recorrido);

    final marcadores = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(marcadores.first.point, coordenadas(recorrido).first);
    expect(marcadores.last.point, coordenadas(recorrido).last);
    expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
    expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);
  });

  testWidgets('encuadra todo el recorrido', (tester) async {
    await montar(tester, recorrido);

    final visible = camara(tester).visibleBounds;
    for (final coordenada in coordenadas(recorrido)) {
      expect(
        visible.contains(coordenada),
        isTrue,
        reason: '$coordenada debería verse',
      );
    }
    expect(camara(tester).zoom, lessThanOrEqualTo(MapaTrayecto.zoomCercano));
  });

  testWidgets('si el usuario no se movió, centra ese lugar de cerca y no '
      'dibuja línea', (tester) async {
    final quieto = [
      puntoDePrueba(latitud: 6.2311, longitud: -75.6105),
      puntoDePrueba(latitud: 6.2311, longitud: -75.6105),
    ];
    await montar(tester, quieto);

    expect(camara(tester).center, const LatLng(6.2311, -75.6105));
    expect(camara(tester).zoom, MapaTrayecto.zoomCercano);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
  });

  testWidgets('se puede mover y acercar, pero no girar', (tester) async {
    await montar(tester, recorrido);

    final opciones = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    final gestos = opciones.interactionOptions.flags;
    expect(gestos & InteractiveFlag.drag, isNot(0));
    expect(gestos & InteractiveFlag.pinchZoom, isNot(0));
    expect(gestos & InteractiveFlag.rotate, 0);
  });

  testWidgets('usa los mismos tiles que el mapa del entrenamiento, con su '
      'atribución', (tester) async {
    final tiles = await montar(tester, recorrido);

    final capa = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(capa.urlTemplate, urlTiles);
    expect(tiles.tilesPedidos, greaterThan(0));
    expect(find.text(atribucionMapa), findsOneWidget);
  });
}
