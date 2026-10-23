import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/widgets/tarjeta_aviso.dart';

/// Pruebas del aviso en tarjeta que comparten los avisos de ubicación
/// (SCRUM-248 y SCRUM-249).
void main() {
  Future<void> montar(
    WidgetTester tester, {
    VoidCallback? onBoton,
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: TarjetaAviso(
                icono: Icons.gps_off_outlined,
                titulo: 'No pudimos ubicarte',
                texto:
                    'El GPS no respondió a tiempo. Si estás bajo techo, '
                    'acércate a una ventana e inténtalo de nuevo.',
                etiquetaBoton: 'Reintentar',
                claveBoton: const Key('boton'),
                onBoton: onBoton,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('muestra el icono, qué pasa, qué hacer y el botón', (
    tester,
  ) async {
    await montar(tester, onBoton: () {});

    expect(find.byIcon(Icons.gps_off_outlined), findsOneWidget);
    expect(find.text('No pudimos ubicarte'), findsOneWidget);
    expect(find.textContaining('acércate a una ventana'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('el botón hace lo que se le pasa', (tester) async {
    var toques = 0;
    await montar(tester, onBoton: () => toques++);

    await tester.tap(find.byKey(const Key('boton')));
    await tester.pump();

    expect(toques, 1);
  });

  testWidgets('sin acción, el botón queda desactivado', (tester) async {
    await montar(tester);

    expect(
      tester.widget<FilledButton>(find.byKey(const Key('boton'))).onPressed,
      isNull,
    );
  });

  testWidgets('en la pantalla más estrecha con texto grande no desborda', (
    tester,
  ) async {
    await montar(
      tester,
      onBoton: () {},
      tamano: const Size(320, 568),
      escalaTexto: 1.6,
    );

    expect(tester.takeException(), isNull);
  });
}
