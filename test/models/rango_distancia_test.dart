import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/rango_distancia.dart';

/// Pruebas de los rangos de distancia (SCRUM-273).
void main() {
  test('son los cuatro del planning, de la más corta a la más larga', () {
    expect(
      [for (final rango in RangoDistancia.values) rango.etiqueta],
      ['Menos de 5 km', '5 a 10 km', '10 a 20 km', 'Más de 20 km'],
    );
  });
}
