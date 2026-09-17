import 'dart:math' as math;

import 'package:flutter/material.dart';

/// La "G" de Google dibujada a mano, para no depender de un asset ni de un
/// paquete de SVG. Se reutiliza en registro y login.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _azul = Color(0xFF4285F4);
  static const _verde = Color(0xFF34A853);
  static const _amarillo = Color(0xFFFBBC05);
  static const _rojo = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final grosor = size.width * 0.2;
    final anillo = Rect.fromLTWH(
      grosor / 2,
      grosor / 2,
      size.width - grosor,
      size.height - grosor,
    );
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;

    // Ángulos en grados, en sentido horario desde las 3 en punto.
    // Queda abierto entre 315° y 360°: la boca de la G.
    void arco(Color color, double inicio, double barrido) {
      canvas.drawArc(
        anillo,
        inicio * math.pi / 180,
        barrido * math.pi / 180,
        false,
        pincel..color = color,
      );
    }

    arco(_azul, 0, 45);
    arco(_verde, 45, 100);
    arco(_amarillo, 145, 70);
    arco(_rojo, 215, 100);

    final centro = size.center(Offset.zero);
    canvas.drawRect(
      Rect.fromLTRB(
        centro.dx,
        centro.dy - grosor / 2,
        size.width,
        centro.dy + grosor / 2,
      ),
      Paint()..color = _azul,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
