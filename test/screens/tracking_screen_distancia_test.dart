import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/controles_entrenamiento.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

/// Distancia y ritmo en vivo dentro de la pantalla de entrenamiento
/// (SCRUM-113, SCRUM-115 y SCRUM-116).
void main() {
  late RelojFalso reloj;
  late ProviderContainer container;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    reloj = RelojFalso();
    fuente = FuenteUbicacionFalsa();
    addTearDown(() => fuente.cerrar());
    container = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(reloj.call),
        fuenteUbicacionProvider.overrideWithValue(fuente),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        repositorioPuntosGpsProvider.overrideWithValue(
          RepositorioPuntosGpsFalso(),
        ),
        entrenamientoActualProvider.overrideWithValue('e-123'),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: TrackingScreen(nombreActividad: 'Correr'),
        ),
      ),
    );
    // La pantalla inicia el cronómetro en el primer frame.
    await tester.pump();
  }

  Future<void> correr(WidgetTester tester, Duration cuanto) async {
    reloj.avanzar(cuanto);
    await tester.pump(cuanto);
  }

  /// Emite una lectura [segundos] después del inicio y deja que llegue
  /// a la pantalla (el evento del stream cae después del frame).
  Future<void> emitir(
    WidgetTester tester,
    double latitud, {
    required int segundos,
  }) async {
    fuente.emitir(
      puntoDePrueba(
        latitud: latitud,
        capturadoEn: DateTime(2026, 1, 1, 8).add(Duration(seconds: segundos)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void detener() => container.read(cronometroProvider.notifier).detener();

  testWidgets('arranca en 0.00 km y ritmo 0\'00" mientras no hay ubicación', (
    tester,
  ) async {
    await montar(tester);

    expect(find.text('0.00 km'), findsOneWidget);
    expect(find.text("0'00\""), findsOneWidget);
    expect(find.text('DISTANCIA'), findsOneWidget);
    expect(find.text('RITMO /KM'), findsOneWidget);

    detener();
  });

  testWidgets('la distancia se actualiza en pantalla con cada punto aceptado', (
    tester,
  ) async {
    await montar(tester);

    await emitir(tester, 6.2311, segundos: 0);
    expect(find.text('0.00 km'), findsOneWidget);

    await emitir(tester, 6.2321, segundos: 30); // +111 m
    expect(find.text('0.11 km'), findsOneWidget);

    await emitir(tester, 6.2331, segundos: 60); // +111 m
    expect(find.text('0.22 km'), findsOneWidget);

    detener();
  });

  testWidgets('el ritmo se calcula con el tiempo del cronómetro', (
    tester,
  ) async {
    await montar(tester);

    await emitir(tester, 6.2311, segundos: 0);
    await correr(tester, const Duration(minutes: 5));
    await emitir(tester, 6.2321, segundos: 300); // ≈111 m en 5 min

    // 300 s / 0.11119 km ≈ 2698 s/km → 44'58".
    expect(find.text("44'58\""), findsOneWidget);

    detener();
  });

  testWidgets('el ruido del GPS no mueve la distancia en pantalla', (
    tester,
  ) async {
    await montar(tester);

    await emitir(tester, 6.2311, segundos: 0);
    // Jitter de ~1 m con el usuario quieto.
    await emitir(tester, 6.23111, segundos: 1);
    await emitir(tester, 6.23109, segundos: 2);
    // Salto imposible: 111 m en 1 s.
    await emitir(tester, 6.2321, segundos: 3);

    expect(find.text('0.00 km'), findsOneWidget);

    detener();
  });

  testWidgets('en pausa no suma y al reanudar sigue desde donde iba', (
    tester,
  ) async {
    await montar(tester);

    await emitir(tester, 6.2311, segundos: 0);
    await emitir(tester, 6.2321, segundos: 30); // +111 m
    expect(find.text('0.11 km'), findsOneWidget);

    await tester.tap(find.byKey(ControlesEntrenamiento.clavePausar));
    await tester.pump();
    // El usuario camina 1 km con la actividad en pausa.
    await emitir(tester, 6.2421, segundos: 300);
    expect(find.text('0.11 km'), findsOneWidget);

    await tester.tap(find.byKey(ControlesEntrenamiento.clavePausar));
    await tester.pump();
    await emitir(tester, 6.2421, segundos: 330);
    expect(find.text('0.11 km'), findsOneWidget);

    await emitir(tester, 6.2431, segundos: 360); // +111 m
    expect(find.text('0.22 km'), findsOneWidget);

    detener();
  });

  testWidgets('si se pierde la ubicación conserva la distancia acumulada', (
    tester,
  ) async {
    await montar(tester);

    await emitir(tester, 6.2311, segundos: 0);
    await emitir(tester, 6.2321, segundos: 30); // +111 m

    fuente.fallar(StateError('GPS apagado'));
    await tester.pump();
    await tester.pump();

    expect(find.text('0.11 km'), findsOneWidget);
    expect(find.text('No se pudo obtener tu ubicación.'), findsOneWidget);

    detener();
  });
}
