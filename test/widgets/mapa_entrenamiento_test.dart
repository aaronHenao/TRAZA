import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/mapa_entrenamiento.dart';

import '../utiles/fuente_ubicacion_falsa.dart';

void main() {
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    addTearDown(() => fuente.cerrar());
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fuenteUbicacionProvider.overrideWithValue(fuente)],
        child: const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Column(children: [MapaEntrenamiento()]),
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

  testWidgets('con posición enseña las coordenadas y enciende la píldora',
      (tester) async {
    await montar(tester);

    await emitir(tester, puntoDePrueba(latitud: 6.23112, longitud: -75.61051));

    expect(find.byKey(MapaEntrenamiento.claveNota), findsNothing);
    expect(find.text('6.23112, -75.61051'), findsOneWidget);
    expect(find.text('± 8 m'), findsOneWidget);
    expect(find.text('Ubicación en vivo'), findsOneWidget);
    expect(colorDelPunto(tester), const Color(0xFFD7F204));
  });

  testWidgets('cada posición nueva reemplaza a la anterior', (tester) async {
    await montar(tester);

    await emitir(tester, puntoDePrueba(latitud: 6.23112, longitud: -75.61051));
    await emitir(tester, puntoDePrueba(latitud: 6.23200, longitud: -75.61100));

    expect(find.text('6.23112, -75.61051'), findsNothing);
    expect(find.text('6.23200, -75.61100'), findsOneWidget);
  });

  testWidgets('sin precisión reportada solo muestra las coordenadas',
      (tester) async {
    await montar(tester);

    await emitir(tester, puntoDePrueba(precisionMetros: null));

    expect(find.byKey(MapaEntrenamiento.claveCoordenadas), findsOneWidget);
    expect(find.textContaining(' m'), findsNothing);
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

  testWidgets('el mapa que le pasen ocupa el hueco en lugar del texto',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fuenteUbicacionProvider.overrideWithValue(fuente)],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MapaEntrenamiento(
                  contenido: ColoredBox(
                    key: Key('mapa-real'),
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await emitir(tester, puntoDePrueba());

    expect(find.byKey(const Key('mapa-real')), findsOneWidget);
    expect(find.byKey(MapaEntrenamiento.claveCoordenadas), findsNothing);
  });

  testWidgets('al salir de la pantalla cierra la captura', (tester) async {
    await montar(tester);
    expect(fuente.suscripcionesAbiertas, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(fuente.suscripcionesAbiertas, 0);
  });
}
