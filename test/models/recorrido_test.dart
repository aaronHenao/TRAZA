import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/recorrido.dart';

/// Tramos del recorrido: lo que se recorre entre pausas (BUG-005).
void main() {
  PuntoGps punto(double latitud) => PuntoGps(
    latitud: latitud,
    longitud: -75.6,
    capturadoEn: DateTime(2026, 1, 1, 8),
  );

  List<List<double>> latitudes(Recorrido recorrido) => [
    for (final tramo in recorrido.tramos) [for (final p in tramo) p.latitud],
  ];

  test('sin puntos no hay tramos', () {
    expect(const Recorrido().tramos, isEmpty);
  });

  test('sin pausas todo es un solo tramo', () {
    final recorrido = Recorrido(puntos: [punto(1), punto(2), punto(3)]);
    expect(latitudes(recorrido), [
      [1, 2, 3],
    ]);
  });

  test('cada corte empieza un tramo nuevo', () {
    final recorrido = Recorrido(
      puntos: [punto(1), punto(2), punto(3), punto(4), punto(5)],
      cortes: const [2, 4],
    );
    expect(latitudes(recorrido), [
      [1, 2],
      [3, 4],
      [5],
    ]);
  });

  test('los cortes cuentan para la igualdad', () {
    final puntos = [punto(1), punto(2)];
    expect(
      Recorrido(puntos: puntos, cortes: const [1]),
      isNot(Recorrido(puntos: puntos)),
    );
  });
}
