import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/calculadora_distancia.dart';
import 'package:traza/services/criterio_movimiento.dart';

// 0.001° de latitud ≈ 111.19 m en cualquier longitud.
const double _metrosPorMiliGrado = 111.19;

final DateTime _t0 = DateTime.utc(2026, 1, 1, 10, 0, 0);

PuntoGps _punto({
  double lat = 6.2442,
  double lon = -75.5812,
  int segundos = 0,
  double? precision = 5,
  double? velocidad,
  double? precisionVelocidad,
}) => PuntoGps(
  latitud: lat,
  longitud: lon,
  capturadoEn: _t0.add(Duration(seconds: segundos)),
  precisionMetros: precision,
  velocidadMps: velocidad,
  precisionVelocidadMps: precisionVelocidad,
);

void main() {
  group('haversineMetros', () {
    test('mismo punto → 0', () {
      expect(
        CalculadoraDistancia.haversineMetros(6.24, -75.58, 6.24, -75.58),
        0,
      );
    });

    test('0.001° de latitud ≈ 111.19 m', () {
      final d = CalculadoraDistancia.haversineMetros(0, 0, 0.001, 0);
      expect(d, closeTo(_metrosPorMiliGrado, 0.1));
    });

    test('Medellín → Bogotá ≈ 239 km en línea recta', () {
      final d = CalculadoraDistancia.haversineMetros(
        6.2442,
        -75.5812,
        4.7110,
        -74.0721,
      );
      expect(d / 1000, closeTo(238.7, 1));
    });

    test('es simétrica', () {
      final ida = CalculadoraDistancia.haversineMetros(
        6.24,
        -75.58,
        6.25,
        -75.57,
      );
      final vuelta = CalculadoraDistancia.haversineMetros(
        6.25,
        -75.57,
        6.24,
        -75.58,
      );
      expect(ida, closeTo(vuelta, 1e-9));
    });
  });

  group('CalculadoraDistancia.agregar', () {
    late CalculadoraDistancia calc;

    setUp(() => calc = CalculadoraDistancia());

    test('empieza en 0 sin ancla', () {
      expect(calc.distanciaMetros, 0);
      expect(calc.ultimoPuntoAceptado, isNull);
    });

    test('primer punto se acepta y fija ancla sin sumar distancia', () {
      final p = _punto();
      expect(calc.agregar(p), isTrue);
      expect(calc.distanciaMetros, 0);
      expect(calc.ultimoPuntoAceptado, same(p));
    });

    test('acumula distancia entre puntos consecutivos válidos', () {
      calc.agregar(_punto(lat: 6.2442, segundos: 0));
      calc.agregar(_punto(lat: 6.2452, segundos: 30)); // +111 m
      calc.agregar(_punto(lat: 6.2462, segundos: 60)); // +111 m
      expect(calc.distanciaMetros, closeTo(2 * _metrosPorMiliGrado, 0.5));
    });

    test('descarta punto con precisión peor que el máximo', () {
      calc.agregar(_punto(segundos: 0));
      final malo = _punto(lat: 6.2452, segundos: 10, precision: 40);
      expect(calc.agregar(malo), isFalse);
      expect(calc.distanciaMetros, 0);
      // El ancla no se movió.
      expect(calc.ultimoPuntoAceptado!.latitud, 6.2442);
    });

    test('acepta punto sin precisión reportada (null)', () {
      calc.agregar(_punto(segundos: 0, precision: null));
      expect(
        calc.agregar(_punto(lat: 6.2452, segundos: 30, precision: null)),
        isTrue,
      );
      expect(calc.distanciaMetros, closeTo(_metrosPorMiliGrado, 0.5));
    });

    test('descarta jitter: desplazamiento menor al mínimo', () {
      calc.agregar(_punto(segundos: 0));
      // 0.00001° ≈ 1.1 m < 3 m
      expect(calc.agregar(_punto(lat: 6.24421, segundos: 1)), isFalse);
      expect(calc.agregar(_punto(lat: 6.24419, segundos: 2)), isFalse);
      expect(calc.distanciaMetros, 0);
    });

    test('caminar despacio sí acumula: rechaza hasta superar el umbral', () {
      // 1 m/s en pasos de 0.00001° (~1.1 m). Con 1 m de error el umbral es
      // el mínimo, 3 m → acepta cada ~3 s.
      calc = CalculadoraDistancia(
        criterio: const CriterioMovimiento(factorRuidoPrecision: 1),
      );
      calc.agregar(_punto(lat: 6.24420, segundos: 0, precision: 1));
      var aceptados = 0;
      for (var i = 1; i <= 10; i++) {
        final ok = calc.agregar(
          _punto(lat: 6.24420 + i * 0.00001, segundos: i, precision: 1),
        );
        if (ok) aceptados++;
      }
      // Distancia real recorrida ≈ 11.1 m; la cuerda entre aceptados es casi igual.
      expect(calc.distanciaMetros, closeTo(10 * 1.1119, 1.2));
      expect(aceptados, greaterThanOrEqualTo(3));
      expect(aceptados, lessThan(10));
    });

    test('descarta teleport: velocidad implícita > máxima', () {
      calc.agregar(_punto(segundos: 0));
      // 111 m en 1 s = 111 m/s
      expect(calc.agregar(_punto(lat: 6.2452, segundos: 1)), isFalse);
      expect(calc.distanciaMetros, 0);
    });

    test(
      'tras un teleport rechazado, se recupera solo cuando dt lo permite',
      () {
        calc.agregar(_punto(segundos: 0));
        expect(calc.agregar(_punto(lat: 6.2452, segundos: 1)), isFalse);
        // Mismo sitio 20 s después: 111 m / 20 s = 5.5 m/s → plausible.
        expect(calc.agregar(_punto(lat: 6.2452, segundos: 20)), isTrue);
        expect(calc.distanciaMetros, closeTo(_metrosPorMiliGrado, 0.5));
      },
    );

    test('descarta punto con timestamp igual o anterior al ancla', () {
      calc.agregar(_punto(segundos: 10));
      expect(calc.agregar(_punto(lat: 6.2452, segundos: 10)), isFalse);
      expect(calc.agregar(_punto(lat: 6.2452, segundos: 5)), isFalse);
      expect(calc.distanciaMetros, 0);
    });

    test('velocidad justo en el límite se acepta', () {
      final c = CalculadoraDistancia(
        criterio: const CriterioMovimiento(velocidadMaximaMps: 10),
      );
      c.agregar(_punto(segundos: 0));
      // ~111.19 m en 11.119 s ≈ 10.0 m/s (con margen por redondeo)
      expect(
        c.agregar(
          PuntoGps(
            latitud: 6.2452,
            longitud: -75.5812,
            capturadoEn: _t0.add(const Duration(milliseconds: 11200)),
            precisionMetros: 5,
          ),
        ),
        isTrue,
      );
    });

    test('reiniciarAncla: siguiente punto no suma pero sí se acepta', () {
      calc.agregar(_punto(lat: 6.2442, segundos: 0));
      calc.agregar(_punto(lat: 6.2452, segundos: 30)); // +111 m
      calc.reiniciarAncla();
      expect(calc.ultimoPuntoAceptado, isNull);
      // Usuario se movió 1 km en pausa; no debe contar.
      expect(calc.agregar(_punto(lat: 6.2552, segundos: 600)), isTrue);
      expect(calc.distanciaMetros, closeTo(_metrosPorMiliGrado, 0.5));
      // Y a partir de ahí vuelve a sumar normal.
      calc.agregar(_punto(lat: 6.2562, segundos: 630));
      expect(calc.distanciaMetros, closeTo(2 * _metrosPorMiliGrado, 0.5));
    });

    test('reiniciar: vuelve a 0 y sin ancla', () {
      calc.agregar(_punto(segundos: 0));
      calc.agregar(_punto(lat: 6.2452, segundos: 30));
      calc.reiniciar();
      expect(calc.distanciaMetros, 0);
      expect(calc.ultimoPuntoAceptado, isNull);
    });

    test('parámetros personalizados se respetan', () {
      final c = CalculadoraDistancia(
        precisionMaximaMetros: 100,
        criterio: const CriterioMovimiento(
          desplazamientoMinimoMetros: 0,
          factorRuidoPrecision: 0,
        ),
      );
      c.agregar(_punto(segundos: 0, precision: 80));
      expect(
        c.agregar(_punto(lat: 6.24421, segundos: 1, precision: 80)),
        isTrue,
      );
      expect(c.distanciaMetros, greaterThan(0));
    });
  });

  group('con velocidad Doppler (SCRUM-116)', () {
    late CalculadoraDistancia calc;

    setUp(() => calc = CalculadoraDistancia());

    test('integra velocidad × tiempo aunque la posición sea mala', () {
      // Precisión de 40 m: por posiciones se descartaría todo.
      for (var i = 0; i <= 10; i++) {
        calc.agregar(
          _punto(
            segundos: i,
            precision: 40,
            velocidad: 1.4,
            precisionVelocidad: 0.3,
          ),
        );
      }
      expect(calc.distanciaMetros, closeTo(14, 0.01));
      expect(calc.ultimaVelocidadMps, 1.4);
    });

    test('quieto según el GPS no suma aunque la posición salte', () {
      calc.agregar(
        _punto(segundos: 0, velocidad: 0.1, precisionVelocidad: 0.3),
      );
      // Salto de ~22 m con el receptor diciendo que no se mueve.
      calc.agregar(
        _punto(
          lat: 6.2444,
          segundos: 1,
          velocidad: 0.2,
          precisionVelocidad: 0.3,
        ),
      );
      expect(calc.distanciaMetros, 0);
      expect(calc.ultimaVelocidadMps, 0);
    });

    test('una velocidad menor que su propio error cuenta como reposo', () {
      calc.agregar(
        _punto(segundos: 0, velocidad: 0.8, precisionVelocidad: 0.9),
      );
      calc.agregar(
        _punto(segundos: 1, velocidad: 0.8, precisionVelocidad: 0.9),
      );
      expect(calc.distanciaMetros, 0);
    });

    test('sin precisión de velocidad se mide por posiciones', () {
      calc.agregar(_punto(segundos: 0, velocidad: 3));
      calc.agregar(_punto(lat: 6.2452, segundos: 30, velocidad: 3));
      expect(calc.distanciaMetros, closeTo(_metrosPorMiliGrado, 0.5));
    });

    test('tras un hueco largo no integra: mide por posiciones', () {
      calc.agregar(
        _punto(segundos: 0, velocidad: 1.4, precisionVelocidad: 0.3),
      );
      // 60 s sin lecturas: integrar 1.4 m/s × 60 s inventaría 84 m.
      calc.agregar(
        _punto(
          lat: 6.2445,
          segundos: 60,
          velocidad: 1.4,
          precisionVelocidad: 0.3,
        ),
      );
      expect(calc.distanciaMetros, closeTo(0.3 * _metrosPorMiliGrado, 0.1));
    });

    test('lecturas iniciales sin velocidad no congelan el ancla', () {
      // Como en el teléfono: el GPS arranca sin velocidad durante unos
      // segundos, y esas lecturas no pasan el filtro de posiciones. Antes el
      // ancla se quedaba en la primera y todo lo demás contaba como hueco
      // largo: 6 m caminados marcaban 0 (BUG-001).
      for (var i = 0; i <= 12; i++) {
        calc.agregar(_punto(segundos: i, precision: 12));
      }
      final velocidades = [0.2, 0.3, 1.0, 1.1, 1.2, 1.1, 0.9, 0.2];
      for (var i = 0; i < velocidades.length; i++) {
        calc.agregar(
          _punto(
            segundos: 13 + i,
            precision: 7,
            velocidad: velocidades[i],
            precisionVelocidad: 0.25,
          ),
        );
      }
      // Trapecios con los reposos a 0: 0.5+1.05+1.15+1.15+1.0+0.45 m.
      expect(calc.distanciaMetros, closeTo(5.3, 0.01));
    });

    test('al reanudar no integra la velocidad a través de la pausa', () {
      calc.agregar(
        _punto(segundos: 0, velocidad: 1.4, precisionVelocidad: 0.3),
      );
      calc.reiniciarAncla();
      calc.agregar(
        _punto(segundos: 3, velocidad: 1.4, precisionVelocidad: 0.3),
      );
      expect(calc.distanciaMetros, 0);
    });
  });

  group('simulación con ruido realista del GPS (SCRUM-116)', () {
    // Una lectura por segundo, como pide la app. El ruido de posición es
    // independiente entre lecturas: el peor caso (en la realidad el error
    // cambia despacio y los saltos son menores).
    const metrosPorGrado = 111190.0;

    List<PuntoGps> trayecto({
      required List<double> velocidades,
      required double ruidoPosicionMetros,
      required double precisionMetros,
      double? ruidoVelocidad,
      double? precisionVelocidad,
      int semilla = 7,
    }) {
      final azar = math.Random(semilla);
      double ruido(double amplitud) => (azar.nextDouble() * 2 - 1) * amplitud;
      var recorrido = 0.0;
      final puntos = <PuntoGps>[];
      for (var i = 0; i < velocidades.length; i++) {
        if (i > 0) recorrido += velocidades[i];
        final conDoppler = ruidoVelocidad != null;
        puntos.add(
          _punto(
            lat:
                6.2442 +
                (recorrido + ruido(ruidoPosicionMetros)) / metrosPorGrado,
            lon: -75.5812 + ruido(ruidoPosicionMetros) / metrosPorGrado,
            segundos: i,
            precision: precisionMetros,
            velocidad: conDoppler
                ? math.max(0, velocidades[i] + ruido(ruidoVelocidad))
                : null,
            precisionVelocidad: conDoppler ? precisionVelocidad : null,
          ),
        );
      }
      return puntos;
    }

    double medir(List<PuntoGps> puntos) {
      final calc = CalculadoraDistancia();
      puntos.forEach(calc.agregar);
      return calc.distanciaMetros;
    }

    test('quieto 2 min con 35 m de error: no se inventa distancia', () {
      final puntos = trayecto(
        velocidades: List.filled(120, 0),
        ruidoPosicionMetros: 20,
        precisionMetros: 35,
        ruidoVelocidad: 0.4,
        precisionVelocidad: 0.4,
      );
      expect(medir(puntos), lessThan(2));
    });

    test('caminando 2 min a 1,4 m/s con 35 m de error: ≈168 m', () {
      final puntos = trayecto(
        velocidades: List.filled(121, 1.4),
        ruidoPosicionMetros: 20,
        precisionMetros: 35,
        ruidoVelocidad: 0.2,
        precisionVelocidad: 0.4,
      );
      expect(medir(puntos), closeTo(168, 168 * 0.05));
    });

    test('caminar, parar 1 min y seguir: la parada no suma', () {
      final puntos = trayecto(
        velocidades: [
          ...List.filled(61, 1.4),
          ...List.filled(60, 0),
          ...List.filled(60, 1.4),
        ],
        ruidoPosicionMetros: 20,
        precisionMetros: 35,
        ruidoVelocidad: 0.2,
        precisionVelocidad: 0.4,
      );
      expect(medir(puntos), closeTo(168, 168 * 0.05));
    });

    test('sin Doppler y con buena señal, caminando mide razonable', () {
      final puntos = trayecto(
        velocidades: List.filled(121, 1.4),
        ruidoPosicionMetros: 3,
        precisionMetros: 8,
      );
      expect(medir(puntos), closeTo(168, 168 * 0.2));
    });
  });
}
