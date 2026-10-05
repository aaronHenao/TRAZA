import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/tramos.dart';

/// Separar un recorrido en tramos y pasar de cortes a la columna `tramo`
/// de `puntos_gps` y de vuelta (BUG-005).
void main() {
  group('dividirEnTramos', () {
    test('sin elementos no hay tramos', () {
      expect(dividirEnTramos<int>(const [], const []), isEmpty);
    });

    test('sin cortes todo es un tramo', () {
      expect(dividirEnTramos([1, 2, 3], const []), [
        [1, 2, 3],
      ]);
    });

    test('cada corte empieza un tramo', () {
      expect(dividirEnTramos([1, 2, 3, 4, 5], const [2, 4]), [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });
  });

  group('tramosDesdeCortes', () {
    test('numera cada punto con su tramo', () {
      expect(tramosDesdeCortes(5, const [2, 4]), [0, 0, 1, 1, 2]);
    });

    test('sin cortes todos son del tramo 0', () {
      expect(tramosDesdeCortes(3, const []), [0, 0, 0]);
    });
  });

  group('cortesDesdeTramos', () {
    test('un corte donde cambia el número de tramo', () {
      expect(cortesDesdeTramos(const [0, 0, 1, 1, 2]), [2, 4]);
    });

    test('ida y vuelta conserva los cortes', () {
      const cortes = [1, 3, 6];
      expect(cortesDesdeTramos(tramosDesdeCortes(8, cortes)), cortes);
    });

    test('filas guardadas antes de la columna (todo 0) son un tramo', () {
      expect(cortesDesdeTramos(const [0, 0, 0]), isEmpty);
    });
  });
}
