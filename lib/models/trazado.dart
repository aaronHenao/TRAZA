import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'punto_gps.dart';
import 'tramos.dart';

/// Forma del recorrido para dibujarla en el resumen (SCRUM-119): la polilínea
/// de los puntos GPS guardados, en coordenadas planas y sin deformar.
///
/// Los puntos quedan entre 0 y 1: la dimensión más larga del recorrido mide 1
/// y la otra conserva su proporción. Quien lo dibuja solo tiene que escalarlo
/// a su espacio. Se dibuja una línea por tramo ([tramos]): lo recorrido en
/// pausa no se une (BUG-005).
@immutable
class Trazado {
  const Trazado._({
    required this.puntos,
    required this.ancho,
    required this.alto,
    this.cortes = const [],
  });

  /// [cortes]: índices de [puntosGps] donde empieza un tramo tras una pausa.
  factory Trazado.desdePuntos(
    List<PuntoGps> puntosGps, {
    List<int> cortes = const [],
  }) {
    if (puntosGps.isEmpty) {
      return const Trazado._(puntos: [], ancho: 0, alto: 0);
    }

    // A la escala de un entrenamiento, un grado de longitud mide cos(latitud)
    // veces lo que mide uno de latitud; sin esta corrección el recorrido se
    // vería estirado a lo ancho. La `y` crece hacia el sur para que el norte
    // quede arriba, como en un mapa.
    final latitudMedia =
        puntosGps.fold<double>(0, (suma, punto) => suma + punto.latitud) /
        puntosGps.length;
    final escalaLongitud = math.cos(latitudMedia * math.pi / 180);
    final planos = [
      for (final punto in puntosGps)
        Offset(punto.longitud * escalaLongitud, -punto.latitud),
    ];

    var izquierda = planos.first.dx;
    var derecha = planos.first.dx;
    var arriba = planos.first.dy;
    var abajo = planos.first.dy;
    for (final punto in planos) {
      izquierda = math.min(izquierda, punto.dx);
      derecha = math.max(derecha, punto.dx);
      arriba = math.min(arriba, punto.dy);
      abajo = math.max(abajo, punto.dy);
    }

    final lado = math.max(derecha - izquierda, abajo - arriba);
    // Todos los puntos en el mismo lugar: el usuario no se movió.
    if (lado == 0) {
      return Trazado._(
        puntos: List.filled(planos.length, Offset.zero),
        ancho: 0,
        alto: 0,
        cortes: cortes,
      );
    }

    return Trazado._(
      puntos: [
        for (final punto in planos)
          Offset((punto.dx - izquierda) / lado, (punto.dy - arriba) / lado),
      ],
      ancho: (derecha - izquierda) / lado,
      alto: (abajo - arriba) / lado,
      cortes: cortes,
    );
  }

  /// Puntos del recorrido en orden de captura: el primero es la partida y el
  /// último, la llegada.
  final List<Offset> puntos;

  /// Índices de [puntos] donde empieza un tramo nuevo.
  final List<int> cortes;

  /// [puntos] separados por las pausas.
  List<List<Offset>> get tramos => dividirEnTramos(puntos, cortes);

  /// Ancho y alto del recorrido. El mayor de los dos vale 1, salvo que el
  /// usuario no se haya movido: entonces ambos valen 0.
  final double ancho;
  final double alto;

  bool get estaVacio => puntos.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is Trazado &&
      other.ancho == ancho &&
      other.alto == alto &&
      listEquals(other.puntos, puntos) &&
      listEquals(other.cortes, cortes);

  @override
  int get hashCode =>
      Object.hash(ancho, alto, Object.hashAll(puntos), Object.hashAll(cortes));

  @override
  String toString() =>
      'Trazado(${puntos.length} puntos, ${ancho.toStringAsFixed(2)} x '
      '${alto.toStringAsFixed(2)})';
}
