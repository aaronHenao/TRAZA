import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/features/actividad/presentation/inicio_screen.dart';
import 'package:traza/features/actividad/presentation/widgets/seccion_iniciar_entrenamiento.dart';

/// Pruebas del diseño de la pantalla de inicio (SCRUM-91).
void main() {
  testWidgets('muestra la cabecera del prototipo', (tester) async {
    await _montar(tester, const InicioScreen());

    expect(find.text('Listo para entrenar'), findsOneWidget);
    expect(find.text('Elige tu actividad y comienza'), findsOneWidget);
  });

  testWidgets('muestra la sección para iniciar el entrenamiento', (
    tester,
  ) async {
    await _montar(tester, const InicioScreen());

    expect(
      find.text(
        'Al iniciar verás el cronómetro, tu ubicación y la distancia '
        'recorrida en tiempo real.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Iniciar actividad'), findsOneWidget);
  });

  testWidgets('sin actividad elegida no se puede iniciar', (tester) async {
    await _montar(tester, const InicioScreen());

    expect(find.text('Ninguna actividad seleccionada'), findsOneWidget);
    expect(_botonIniciar(tester).onPressed, isNull);
  });

  testWidgets('el historial queda deshabilitado hasta que exista su pantalla', (
    tester,
  ) async {
    await _montar(tester, const InicioScreen());

    expect(find.byTooltip('Historial'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  group('sección para iniciar el entrenamiento', () {
    testWidgets('con una actividad la muestra y habilita el botón', (
      tester,
    ) async {
      var iniciado = false;
      await _montar(
        tester,
        Scaffold(
          body: SeccionIniciarEntrenamiento(
            actividad: 'Correr',
            onIniciar: () => iniciado = true,
          ),
        ),
      );

      expect(find.text('Correr'), findsOneWidget);
      expect(find.text('Ninguna actividad seleccionada'), findsNothing);

      await tester.tap(find.text('Iniciar actividad'));
      expect(iniciado, isTrue);
    });

    testWidgets('con actividad pero sin acción conectada sigue deshabilitado', (
      tester,
    ) async {
      await _montar(
        tester,
        const Scaffold(
          body: SeccionIniciarEntrenamiento(actividad: 'Correr', onIniciar: null),
        ),
      );

      expect(_botonIniciar(tester).onPressed, isNull);
    });
  });
}

Future<void> _montar(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: pantalla));
}

FilledButton _botonIniciar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));
