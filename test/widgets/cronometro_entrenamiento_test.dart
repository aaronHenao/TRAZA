import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/widgets/cronometro_entrenamiento.dart';

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

  Future<void> montar(WidgetTester tester) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: CronometroEntrenamiento(),
          ),
        ),
      ),
    );
  }

  /// Deja correr el reloj real y el falso a la vez.
  Future<void> correr(WidgetTester tester, Duration cuanto) async {
    reloj.avanzar(cuanto);
    await tester.pump(cuanto);
  }

  String tiempoEnPantalla(WidgetTester tester) {
    return tester
        .widget<Text>(find.byKey(CronometroEntrenamiento.claveTiempo))
        .data!;
  }

  testWidgets('muestra el cronómetro en cero antes de arrancar',
      (tester) async {
    await montar(tester);

    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('TIEMPO'), findsOneWidget);
  });

  testWidgets('arranca en cero cuando inicia la actividad', (tester) async {
    await montar(tester);

    container.read(cronometroProvider.notifier).iniciar();
    await tester.pump();

    expect(tiempoEnPantalla(tester), '00:00:00');

    container.read(cronometroProvider.notifier).detener();
  });

  testWidgets('se actualiza continuamente mientras la actividad corre',
      (tester) async {
    await montar(tester);
    container.read(cronometroProvider.notifier).iniciar();
    await tester.pump();

    await correr(tester, const Duration(seconds: 1));
    expect(tiempoEnPantalla(tester), '00:00:01');

    await correr(tester, const Duration(seconds: 1));
    expect(tiempoEnPantalla(tester), '00:00:02');

    await correr(tester, const Duration(seconds: 58));
    expect(tiempoEnPantalla(tester), '00:01:00');

    await correr(tester, const Duration(hours: 1, seconds: 5));
    expect(tiempoEnPantalla(tester), '01:01:05');

    container.read(cronometroProvider.notifier).detener();
  });

  testWidgets('en pausa congela el tiempo y lo avisa en la etiqueta',
      (tester) async {
    await montar(tester);
    container.read(cronometroProvider.notifier).iniciar();
    await correr(tester, const Duration(seconds: 12));

    container.read(cronometroProvider.notifier).pausar();
    await tester.pump();

    expect(tiempoEnPantalla(tester), '00:00:12');
    expect(find.text('EN PAUSA'), findsOneWidget);
    expect(find.text('TIEMPO'), findsNothing);

    await correr(tester, const Duration(minutes: 3));
    expect(tiempoEnPantalla(tester), '00:00:12');

    container.read(cronometroProvider.notifier).reanudar();
    await correr(tester, const Duration(seconds: 3));

    expect(tiempoEnPantalla(tester), '00:00:15');
    expect(find.text('TIEMPO'), findsOneWidget);

    container.read(cronometroProvider.notifier).detener();
  });

  testWidgets('recupera el tiempo real tras volver de segundo plano',
      (tester) async {
    await montar(tester);
    container.read(cronometroProvider.notifier).iniciar();
    await tester.pump();

    // La app se va a segundo plano: el reloj del sistema sigue, pero
    // no llega ningún tick a la interfaz.
    reloj.avanzar(const Duration(minutes: 9, seconds: 30));
    container.read(cronometroProvider.notifier).sincronizar();
    await tester.pump();

    expect(tiempoEnPantalla(tester), '00:09:30');

    container.read(cronometroProvider.notifier).detener();
  });
}
