import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/mapa_entrenamiento.dart';
import 'package:traza/widgets/mapa_recorrido.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    addTearDown(() => fuente.cerrar());
  });

  Future<void> montar(WidgetTester tester, {Widget? contenido}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fuenteUbicacionProvider.overrideWithValue(fuente),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Column(children: [MapaEntrenamiento(contenido: contenido)]),
          ),
        ),
      ),
    );
  }

  /// Emite una posición y deja que el provider y el widget se actualicen.
  Future<void> emitir(WidgetTester tester, PuntoGps punto) async {
    fuente.emitir(punto);
    await tester.pump();
    await tester.pump();
  }

  Color colorDelPunto(WidgetTester tester) {
    final punto = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle);
    return punto.color!;
  }

  testWidgets('al entrar abre la captura y avisa mientras busca señal',
      (tester) async {
    await montar(tester);

    expect(fuente.suscripcionesAbiertas, 1);
    expect(find.text('Buscando tu ubicación...'), findsOneWidget);
    expect(colorDelPunto(tester), isNot(const Color(0xFFD7F204)));
  });

  testWidgets('con posición quita la nota y enciende la píldora',
      (tester) async {
    await montar(tester);

    await emitir(tester, puntoDePrueba());

    expect(find.byKey(MapaEntrenamiento.claveNota), findsNothing);
    expect(find.text('Ubicación en vivo'), findsOneWidget);
    expect(colorDelPunto(tester), const Color(0xFFD7F204));
  });

  testWidgets('por defecto dibuja el mapa del recorrido', (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    expect(find.byType(MapaRecorrido), findsOneWidget);
    expect(find.byKey(MapaRecorrido.claveMarcador), findsOneWidget);
  });

  testWidgets('si la fuente falla a mitad de la actividad lo avisa',
      (tester) async {
    await montar(tester);
    await emitir(tester, puntoDePrueba());

    fuente.fallar(StateError('GPS perdido'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No se pudo obtener tu ubicación.'), findsOneWidget);
  });

  testWidgets('el contenido que le pasen reemplaza al mapa', (tester) async {
    await montar(
      tester,
      contenido: const ColoredBox(key: Key('otro-mapa'), color: Colors.green),
    );
    await emitir(tester, puntoDePrueba());

    expect(find.byKey(const Key('otro-mapa')), findsOneWidget);
    expect(find.byType(MapaRecorrido), findsNothing);
  });

  testWidgets('al salir de la pantalla cierra la captura', (tester) async {
    await montar(tester);
    expect(fuente.suscripcionesAbiertas, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(fuente.suscripcionesAbiertas, 0);
  });
}
