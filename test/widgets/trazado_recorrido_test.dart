import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/trazado.dart';
import 'package:traza/theme/app_colors.dart';
import 'package:traza/widgets/trazado_recorrido.dart';

/// Pruebas del dibujo del trazado en el resumen (SCRUM-119).
///
/// El recuadro de prueba mide 300 x 160, como el del resumen en un teléfono
/// de ancho parecido: con el margen de 20 queda un área útil de 260 x 120
/// centrada en (150, 80).
void main() {
  PuntoGps punto(double latitud, double longitud) => PuntoGps(
    latitud: latitud,
    longitud: longitud,
    capturadoEn: DateTime(2026, 1, 1, 8),
  );

  Future<void> dibujar(WidgetTester tester, Trazado trazado) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 160,
            child: TrazadoRecorrido(trazado: trazado),
          ),
        ),
      ),
    );
  }

  Finder lienzo() => find.descendant(
    of: find.byType(TrazadoRecorrido),
    matching: find.byType(CustomPaint),
  );

  testWidgets('dibuja la línea en lima, la partida en blanco y la llegada en '
      'lima', (tester) async {
    // Recta de sur a norte: ocupa todo el alto útil, centrada a lo ancho.
    await dibujar(
      tester,
      Trazado.desdePuntos([punto(6.20, -75.6), punto(6.21, -75.6)]),
    );

    expect(
      lienzo(),
      paints
        ..path(
          color: AppColors.accent,
          strokeWidth: TrazadoRecorrido.grosorLinea,
          style: PaintingStyle.stroke,
        )
        ..circle(x: 150, y: 140, radius: 5, color: Colors.white)
        ..circle(x: 150, y: 20, radius: 5, color: AppColors.accent),
    );
  });

  testWidgets('encaja el recorrido en el recuadro sin deformarlo', (
    tester,
  ) async {
    // Un cuadrado de 0.001° centrado en el ecuador, donde la corrección de la
    // longitud vale exactamente 1. En un recuadro ancho lo limita el alto
    // (120): mide 120 x 120 y queda centrado, de x = 90 a x = 210.
    await dibujar(
      tester,
      Trazado.desdePuntos([
        punto(-0.0005, 0),
        punto(-0.0005, 0.001),
        punto(0.0005, 0.001),
        punto(0.0005, 0),
      ]),
    );

    expect(
      lienzo(),
      paints
        ..path()
        // Sale abajo a la izquierda y, tras dar la vuelta, llega arriba a la
        // izquierda.
        ..circle(x: 90, y: 140, color: Colors.white)
        ..circle(x: 90, y: 20, color: AppColors.accent),
    );
  });

  testWidgets('con un solo punto marca el lugar sin dibujar línea', (
    tester,
  ) async {
    await dibujar(tester, Trazado.desdePuntos([punto(6.2311, -75.6105)]));

    expect(
      lienzo(),
      paints
        ..circle(x: 150, y: 80, color: Colors.white)
        ..circle(x: 150, y: 80, color: AppColors.accent),
    );
    expect(lienzo(), isNot(paints..path()));
  });

  testWidgets('se anuncia como imagen del recorrido', (tester) async {
    await dibujar(
      tester,
      Trazado.desdePuntos([punto(6.20, -75.6), punto(6.21, -75.6)]),
    );

    expect(
      find.bySemanticsLabel('Recorrido del entrenamiento'),
      findsOneWidget,
    );
  });
}
