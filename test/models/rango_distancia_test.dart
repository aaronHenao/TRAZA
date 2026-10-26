import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/widgets/tarjeta_reto.dart';

/// Pruebas de los rangos de distancia (SCRUM-273 y SCRUM-274).
void main() {
  test('son los cuatro del planning, de la más corta a la más larga', () {
    expect(
      [for (final rango in RangoDistancia.values) rango.etiqueta],
      ['Menos de 5 km', '5 a 10 km', '10 a 20 km', 'Más de 20 km'],
    );
  });

  group('el rango de una distancia (SCRUM-274)', () {
    test('cada distancia cae en el rango que la nombra', () {
      expect(RangoDistancia.de(0), RangoDistancia.menosDe5);
      expect(RangoDistancia.de(3.2), RangoDistancia.menosDe5);
      expect(RangoDistancia.de(7.5), RangoDistancia.de5a10);
      expect(RangoDistancia.de(15), RangoDistancia.de10a20);
      expect(RangoDistancia.de(42.2), RangoDistancia.masDe20);
    });

    test('en los bordes va a uno solo: 5 y 10 km son de "5 a 10 km", y 20 '
        'km, de "10 a 20 km"', () {
      expect(RangoDistancia.de(4.99), RangoDistancia.menosDe5);
      expect(RangoDistancia.de(5), RangoDistancia.de5a10);
      expect(RangoDistancia.de(10), RangoDistancia.de5a10);
      expect(RangoDistancia.de(10.01), RangoDistancia.de10a20);
      expect(RangoDistancia.de(20), RangoDistancia.de10a20);
      expect(RangoDistancia.de(20.01), RangoDistancia.masDe20);
    });

    test('mira la distancia como la muestra la tarjeta, en centésimas', () {
      // Lo que mide, lo que dice la tarjeta y el rango en el que se busca.
      const casos = [
        (4.994, '4.99', RangoDistancia.menosDe5),
        (4.996, '5', RangoDistancia.de5a10),
        (10.004, '10', RangoDistancia.de5a10),
        (10.006, '10.01', RangoDistancia.de10a20),
        (20.004, '20', RangoDistancia.de10a20),
        (20.006, '20.01', RangoDistancia.masDe20),
      ];
      for (final (km, enLaTarjeta, rango) in casos) {
        expect(TarjetaReto.textoKm(km), enLaTarjeta, reason: '$km km');
        expect(RangoDistancia.de(km), rango, reason: '$km km');
      }
    });
  });

  group('si una distancia entra en un rango (SCRUM-274)', () {
    test('cada una entra en uno solo, el suyo', () {
      for (final km in [0.0, 2.5, 4.999, 5.0, 8.0, 10.0, 10.5, 20.0, 21.0]) {
        expect(
          [
            for (final rango in RangoDistancia.values)
              if (rango.contiene(km)) rango,
          ],
          [RangoDistancia.de(km)],
          reason: '$km km',
        );
      }
    });

    test('una ruta sin distancia registrada no entra en ninguno', () {
      for (final rango in RangoDistancia.values) {
        expect(rango.contiene(null), isFalse, reason: rango.etiqueta);
      }
    });
  });
}
