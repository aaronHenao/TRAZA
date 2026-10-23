import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/ruta.dart';
import '../theme/app_colors.dart';
import '../theme/traza_theme.dart';

/// La forma de una ruta en pequeño (SCRUM-247).
///
/// Es un mapa sin mapa: la línea del recorrido sobre el mismo fondo oscuro
/// del mapa del entrenamiento, con la partida en blanco y la llegada en lima,
/// como `MapaTrayecto`. No carga tiles a propósito: una lista de rutas
/// pediría un mapa por tarjeta, y para reconocer una vuelta, una ida y
/// vuelta o una subida basta con la forma.
///
/// Con menos de dos puntos distintos no hay forma que dibujar, y en su lugar
/// va el icono de ruta.
class MiniaturaRuta extends StatelessWidget {
  const MiniaturaRuta({required this.puntos, super.key});

  /// Los puntos de `Ruta.miniatura`, en el orden del recorrido.
  final List<PuntoRuta> puntos;

  /// Lo que se deja libre alrededor de la línea, para que la partida y la
  /// llegada no queden cortadas contra el borde.
  static const margen = 8.0;

  static const grosorLinea = 2.5;

  static const claveSinForma = Key('miniatura-ruta-sin-forma');

  /// Lleva [puntos] al recuadro de [tamano], con el norte arriba y sin
  /// deformar la ruta: la escala es la misma a lo ancho y a lo alto, y lo que
  /// sobra se reparte a los dos lados.
  ///
  /// La longitud se encoge con el coseno de la latitud porque un grado de
  /// longitud mide menos cuanto más lejos se está del ecuador. En Medellín
  /// casi no se nota, pero sin esto una ruta saldría más ancha de lo que es.
  static List<Offset> proyectar(List<PuntoRuta> puntos, Size tamano) {
    if (puntos.isEmpty) return const [];

    final latitudMedia =
        puntos.map((p) => p.latitud).reduce((a, b) => a + b) / puntos.length;
    final factorLongitud = math.cos(latitudMedia * math.pi / 180);

    final xs = [for (final punto in puntos) punto.longitud * factorLongitud];
    final ys = [for (final punto in puntos) punto.latitud];
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);

    final anchoRuta = maxX - minX;
    final altoRuta = maxY - minY;

    // Todos en el mismo lugar: no hay forma, se quedan en el centro.
    if (anchoRuta == 0 && altoRuta == 0) {
      return [for (final _ in puntos) tamano.center(Offset.zero)];
    }

    final anchoUtil = math.max(tamano.width - 2 * margen, 0.0);
    final altoUtil = math.max(tamano.height - 2 * margen, 0.0);
    final escala = math.min(
      anchoRuta > 0 ? anchoUtil / anchoRuta : double.infinity,
      altoRuta > 0 ? altoUtil / altoRuta : double.infinity,
    );

    final izquierda = (tamano.width - anchoRuta * escala) / 2;
    final arriba = (tamano.height - altoRuta * escala) / 2;

    return [
      for (var i = 0; i < puntos.length; i++)
        Offset(
          izquierda + (xs[i] - minX) * escala,
          // El norte arriba: a más latitud, más cerca del borde de arriba.
          arriba + (maxY - ys[i]) * escala,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hayForma = puntos.toSet().length > 1;

    // Decorativa: el nombre y los datos de la ruta van en texto al lado, y
    // un lector de pantalla no tiene nada útil que decir de una línea.
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: TrazaColors.trackingTop,
          child: hayForma
              ? CustomPaint(
                  painter: _PintorMiniatura(puntos),
                  size: Size.infinite,
                )
              : const Center(
                  child: Icon(
                    Icons.route_outlined,
                    key: claveSinForma,
                    size: 22,
                    color: AppColors.accent,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PintorMiniatura extends CustomPainter {
  _PintorMiniatura(this.puntos);

  final List<PuntoRuta> puntos;

  @override
  void paint(Canvas canvas, Size size) {
    final enPantalla = MiniaturaRuta.proyectar(puntos, size);

    final camino = Path()..moveTo(enPantalla.first.dx, enPantalla.first.dy);
    for (final punto in enPantalla.skip(1)) {
      camino.lineTo(punto.dx, punto.dy);
    }

    canvas.drawPath(
      camino,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = MiniaturaRuta.grosorLinea
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // La llegada encima de la partida, como en `MapaTrayecto`: en una
    // vuelta las dos caen en el mismo sitio y se ve dónde termina.
    _extremo(canvas, enPantalla.first, Colors.white);
    _extremo(canvas, enPantalla.last, AppColors.accent);
  }

  /// Un punto con un borde del color del fondo, para que se despegue de la
  /// línea que pasa por debajo.
  void _extremo(Canvas canvas, Offset centro, Color color) {
    canvas
      ..drawCircle(centro, 4.5, Paint()..color = TrazaColors.trackingTop)
      ..drawCircle(centro, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PintorMiniatura anterior) =>
      !listEquals(anterior.puntos, puntos);
}
