import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

/// Distancia y ritmo en vivo dentro de la pantalla de entrenamiento
/// (SCRUM-113).
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





}
