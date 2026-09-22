import 'package:flutter/foundation.dart';

/// Un trozo de recorrido entre dos puntos GPS que la calculadora aceptó
/// (SCRUM-111).
///
/// Es la unidad con la que se mide el ritmo actual: la distancia sola no
/// basta, hace falta saber *cuándo* se recorrió para poder quedarse con lo
/// de los últimos segundos y descartar lo viejo.
@immutable
class TramoRecorrido {
  const TramoRecorrido({
    required this.metros,
    required this.inicio,
    required this.fin,
  });

  /// Distancia del tramo, en metros.
  final double metros;

  /// Instante de captura del punto ancla (dónde empezaba el tramo).
  final DateTime inicio;

  /// Instante de captura del punto que cerró el tramo.
  final DateTime fin;

  /// Lo que se tardó en recorrerlo.
  Duration get duracion => fin.difference(inicio);

  @override
  bool operator ==(Object other) =>
      other is TramoRecorrido &&
      other.metros == metros &&
      other.inicio == inicio &&
      other.fin == fin;

  @override
  int get hashCode => Object.hash(metros, inicio, fin);

  @override
  String toString() => 'TramoRecorrido($metros m en ${duracion.inSeconds} s)';
}
