import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/widgets/controles_entrenamiento.dart';
import 'package:traza/widgets/cronometro_entrenamiento.dart';
import 'package:traza/widgets/estadisticas_entrenamiento.dart';
import 'package:traza/widgets/mapa_entrenamiento.dart';

import '../utiles/reloj_falso.dart';

void main() {
  late RelojFalso reloj;
  late ProviderContainer container;

  setUp(() {
    reloj = RelojFalso();
    container = ProviderContainer(
      overrides: [relojProvider.overrideWithValue(reloj.call)],
    );
    addTearDown(container.dispose);
  });

  Future<void> montar(
    WidgetTester tester, {
    void Function(Duration duracion)? onFinalizar,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: TrackingScreen(
            nombreActividad: 'Correr',
            onFinalizar: onFinalizar,
          ),
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

  String tiempoEnPantalla(WidgetTester tester) {
    return tester
        .widget<Text>(find.byKey(CronometroEntrenamiento.claveTiempo))
        .data!;
  }

  void detener() => container.read(cronometroProvider.notifier).detener();

  testWidgets('arma la pantalla con el mapa, el cronómetro, las métricas '
      'y los botones de pausar y finalizar', (tester) async {
    await montar(tester);

    expect(find.byType(MapaEntrenamiento), findsOneWidget);
    expect(find.byType(CronometroEntrenamiento), findsOneWidget);
    expect(find.byType(EstadisticasEntrenamiento), findsOneWidget);
    expect(find.byKey(ControlesEntrenamiento.clavePausar), findsOneWidget);
    expect(find.byKey(ControlesEntrenamiento.claveFinalizar), findsOneWidget);
    expect(find.text('Correr'), findsOneWidget);

    detener();
  });

  testWidgets('el cronómetro arranca en cero al entrar a la pantalla',
      (tester) async {
    await montar(tester);

    expect(tiempoEnPantalla(tester), '00:00:00');
    expect(container.read(cronometroProvider).estaEnCurso, isTrue);

    detener();
  });

  testWidgets('el cronómetro avanza mientras el usuario hace su ruta',
      (tester) async {
    await montar(tester);

    await correr(tester, const Duration(seconds: 5));
    expect(tiempoEnPantalla(tester), '00:00:05');

    await correr(tester, const Duration(minutes: 2, seconds: 3));
    expect(tiempoEnPantalla(tester), '00:02:08');

    detener();
  });

  testWidgets('el botón de pausa congela y reanuda el cronómetro',
      (tester) async {
    await montar(tester);
    await correr(tester, const Duration(seconds: 20));

    await tester.tap(find.byKey(ControlesEntrenamiento.clavePausar));
    await tester.pump();

    expect(container.read(cronometroProvider).estaPausado, isTrue);

    await correr(tester, const Duration(minutes: 1));
    expect(tiempoEnPantalla(tester), '00:00:20');

    await tester.tap(find.byKey(ControlesEntrenamiento.clavePausar));
    await tester.pump();
    await correr(tester, const Duration(seconds: 4));

    expect(tiempoEnPantalla(tester), '00:00:24');

    detener();
  });

  testWidgets('finalizar detiene el cronómetro y reporta el tiempo total',
      (tester) async {
    Duration? reportada;
    await montar(tester, onFinalizar: (duracion) => reportada = duracion);

    await correr(tester, const Duration(minutes: 32, seconds: 17));
    await tester.tap(find.byKey(ControlesEntrenamiento.claveFinalizar));
    await tester.pump();

    expect(reportada, const Duration(minutes: 32, seconds: 17));
    expect(container.read(cronometroProvider).estaEnCurso, isFalse);

    // Ya detenido, el tiempo mostrado no se mueve más.
    await correr(tester, const Duration(minutes: 5));
    expect(tiempoEnPantalla(tester), '00:32:17');
  });
}
