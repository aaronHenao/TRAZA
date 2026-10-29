import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/simplificador_trazado.dart';

/// Simplificación del recorrido por Douglas-Peucker (RNF-06): quitar los
/// puntos que no cambian la forma, respetar las pausas y no pasar nunca del
/// tope.
void main() {
  PuntoGps punto(double lat, double lng) => PuntoGps(
    latitud: lat,
    longitud: lng,
    capturadoEn: DateTime(2026, 10, 17, 7),
  );

  /// Un paso de latitud ≈ 11,1 m.
  const paso = 1 / 10000;

  /// Cuántos metros de longitud mide un grado a la latitud de Medellín.
  final metrosPorGradoLongitud = 111320 * math.cos(6.2442 * math.pi / 180);

  group('qué se conserva', () {
    test('una recta se queda en sus dos extremos', () {
      final recta = [
        for (var i = 0; i < 500; i++) punto(6.2442 + i * paso, -75.5812),
      ];

      final indices = indicesQueConserva(recta);

      expect(indices, [0, 499]);
    });

    test('un vértice se conserva si se separa más que la tolerancia', () {
      // El punto del medio se va 20 m al este de la línea que une los
      // otros dos: cuatro veces la tolerancia.
      final desvio = 20 / metrosPorGradoLongitud;
      final puntos = [
        punto(6.2442, -75.5812),
        punto(6.2452, -75.5812 + desvio),
        punto(6.2462, -75.5812),
      ];

      expect(indicesQueConserva(puntos), [0, 1, 2]);
    });

    test('un vértice se quita si se separa menos que la tolerancia', () {
      // 2 m: por debajo de los 5 m, es ruido del GPS y no forma.
      final desvio = 2 / metrosPorGradoLongitud;
      final puntos = [
        punto(6.2442, -75.5812),
        punto(6.2452, -75.5812 + desvio),
        punto(6.2462, -75.5812),
      ];

      expect(indicesQueConserva(puntos), [0, 2]);
    });

    test('la tolerancia se puede subir y quita más', () {
      final desvio = 20 / metrosPorGradoLongitud;
      final puntos = [
        punto(6.2442, -75.5812),
        punto(6.2452, -75.5812 + desvio),
        punto(6.2462, -75.5812),
      ];

      expect(indicesQueConserva(puntos, toleranciaMetros: 50), [0, 2]);
    });

    test('dos puntos o menos se devuelven tal cual', () {
      expect(indicesQueConserva([]), isEmpty);
      expect(indicesQueConserva([punto(6.24, -75.58)]), [0]);
      expect(indicesQueConserva([punto(6.24, -75.58), punto(6.25, -75.58)]), [
        0,
        1,
      ]);
    });
  });

  group('ruta circular', () {
    test('un recorrido que acaba donde empezó conserva su forma', () {
      // El segmento entre el primer y el último punto mide cero, así que no
      // hay recta sobre la que proyectar: la distancia se mide al punto. Si
      // no se tratara aparte, la primera división daría NaN y el recorrido
      // entero se colapsaría a dos puntos.
      final radio = 300 / 111320;
      final circulo = [
        for (var i = 0; i <= 60; i++)
          punto(
            6.2442 + radio * math.cos(i * 2 * math.pi / 60),
            -75.5812 +
                radio *
                    math.sin(i * 2 * math.pi / 60) /
                    math.cos(6.2442 * math.pi / 180),
          ),
      ];

      final indices = indicesQueConserva(circulo);

      // Un círculo de 300 m de radio no se puede dibujar con dos puntos.
      expect(indices.length, greaterThan(8));
      expect(indices.first, 0);
      expect(indices.last, 60);
    });
  });

  group('el tope', () {
    test('nunca devuelve más de lo que se le pide', () {
      // Zigzag: cambia de dirección en cada punto, así que con la
      // tolerancia por defecto habría que conservarlos todos.
      final zigzag = [
        for (var i = 0; i < 3000; i++)
          punto(6.2442 + i * paso, -75.5812 + (i.isEven ? 0 : paso * 3)),
      ];

      final resultado = simplificarRecorrido(zigzag, maximo: 500);

      expect(resultado.puntos.length, lessThanOrEqualTo(500));
      expect(resultado.puntos.length, greaterThan(2));
    });

    test('conserva la partida y la llegada aunque suba la tolerancia', () {
      final zigzag = [
        for (var i = 0; i < 3000; i++)
          punto(6.2442 + i * paso, -75.5812 + (i.isEven ? 0 : paso * 3)),
      ];

      final resultado = simplificarRecorrido(zigzag, maximo: 20);

      expect(resultado.puntos.length, lessThanOrEqualTo(20));
      expect(resultado.puntos.first, zigzag.first);
      expect(resultado.puntos.last, zigzag.last);
    });

    test('un recorrido de 10 km cabe de sobra en 500 puntos (RNF-06)', () {
      // 2000 puntos es lo que deja un GPS que graba cada 5 m en 10 km, con
      // una curva cada 12 puntos (~130 m), que es más revirado que una
      // calle real.
      final diezKm = [
        for (var i = 0; i <= 2000; i++)
          punto(
            6.2442 + i * paso,
            -75.5812 +
                25 / metrosPorGradoLongitud * math.sin(i * 2 * math.pi / 12),
          ),
      ];

      final resultado = simplificarRecorrido(diezKm, maximo: 500);

      expect(resultado.puntos.length, lessThanOrEqualTo(500));
      // Conservando la forma: no es que se haya quedado en dos.
      expect(resultado.puntos.length, greaterThan(50));
    });
  });

  group('las pausas', () {
    test('cada tramo se simplifica aparte y los cortes se recolocan', () {
      // Dos rectas separadas por una pausa. Si se simplificara la lista
      // entera de una vez, quedarían dos puntos y el corte no apuntaría a
      // nada: se dibujaría una sola línea atravesando la pausa (BUG-005).
      final puntos = [
        for (var i = 0; i < 50; i++) punto(6.2442 + i * paso, -75.5812),
        for (var i = 0; i < 50; i++) punto(6.2600 + i * paso, -75.5812),
      ];

      final resultado = simplificarRecorrido(
        puntos,
        maximo: 500,
        cortes: const [50],
      );

      // Dos extremos por tramo.
      expect(resultado.puntos.length, 4);
      expect(resultado.cortes, [2]);
      expect(resultado.puntos.first, puntos.first);
      expect(resultado.puntos.last, puntos.last);
      // El corte separa el final del primer tramo del inicio del segundo.
      expect(resultado.puntos[1], puntos[49]);
      expect(resultado.puntos[2], puntos[50]);
    });

    test('sin pausas no hay cortes que devolver', () {
      final puntos = [
        for (var i = 0; i < 50; i++) punto(6.2442 + i * paso, -75.5812),
      ];

      expect(simplificarRecorrido(puntos, maximo: 500).cortes, isEmpty);
    });
  });

  test('un recorrido de miles de puntos no desborda la pila', () {
    // Douglas-Peucker parte el recorrido en el punto más lejano, y esa
    // partición no está equilibrada: en el peor caso anida tantos niveles
    // como puntos haya. Con recursión esto reventaría; con pila propia, no.
    //
    // Una escalera creciente es justo ese peor caso: cada división deja un
    // lado de un solo punto y el otro con todo el resto.
    final escalera = [
      for (var i = 0; i < 20000; i++)
        punto(6.2442 + i * paso, -75.5812 + i * i * paso / 20000),
    ];

    expect(() => simplificarRecorrido(escalera, maximo: 500), returnsNormally);
  });
}
