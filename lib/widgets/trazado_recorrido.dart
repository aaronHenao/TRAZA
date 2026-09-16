import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/trazado.dart';
import '../theme/app_colors.dart';

/// Dibuja el trazado del recorrido como `.summary-map` del prototipo
/// (SCRUM-119): la línea en lima, el punto de partida en blanco y el de
/// llegada en lima.
///
/// Ocupa todo el espacio que le den y centra el recorrido dentro, sin
/// deformarlo.
class TrazadoRecorrido extends StatelessWidget {
  const TrazadoRecorrido({required this.trazado, super.key});

  final Trazado trazado;

  /// Espacio libre alrededor del recorrido, para que la partida y la llegada
  /// no queden cortadas en el borde.
  static const margen = 20.0;

  /// Medidas del prototipo: `stroke-width="3"` y círculos de radio 5.
  static const grosorLinea = 3.0;
  static const radioExtremos = 5.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Recorrido del entrenamiento',
      image: true,
      child: CustomPaint(size: Size.infinite, painter: _PintorTrazado(trazado)),
    );
  }
}

class _PintorTrazado extends CustomPainter {
  const _PintorTrazado(this.trazado);

  final Trazado trazado;

  @override
  void paint(Canvas canvas, Size size) {
    if (trazado.estaVacio) return;

    const margen = TrazadoRecorrido.margen;
    final area = Rect.fromLTRB(
      margen,
      margen,
      size.width - margen,
      size.height - margen,
    );
    // Se escala por el lado que primero se llena, para no deformar el
    // recorrido. Una dimensión que mide 0 (una recta) no limita.
    final escala = math.min(
      trazado.ancho == 0 ? double.infinity : area.width / trazado.ancho,
      trazado.alto == 0 ? double.infinity : area.height / trazado.alto,
    );
    // Si el usuario no se movió, todo queda en el centro.
    final factor = escala.isFinite ? escala : 0.0;
    final origen =
        area.center - Offset(trazado.ancho, trazado.alto) * factor / 2;
    Offset enPantalla(Offset punto) => origen + punto * factor;

    final puntos = trazado.puntos;
    if (puntos.length > 1) {
      final inicio = enPantalla(puntos.first);
      final linea = Path()..moveTo(inicio.dx, inicio.dy);
      for (final punto in puntos.skip(1)) {
        final enLinea = enPantalla(punto);
        linea.lineTo(enLinea.dx, enLinea.dy);
      }
      canvas.drawPath(
        linea,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = TrazadoRecorrido.grosorLinea
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Los extremos van encima de la línea.
    canvas
      ..drawCircle(
        enPantalla(puntos.first),
        TrazadoRecorrido.radioExtremos,
        Paint()..color = Colors.white,
      )
      ..drawCircle(
        enPantalla(puntos.last),
        TrazadoRecorrido.radioExtremos,
        Paint()..color = AppColors.accent,
      );
  }

  @override
  bool shouldRepaint(_PintorTrazado anterior) => anterior.trazado != trazado;
}
