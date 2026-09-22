import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/calculadora_distancia.dart';

// 0.001° de latitud ≈ 111.19 m en cualquier longitud.
const double _metrosPorMiliGrado = 111.19;

final DateTime _t0 = DateTime.utc(2026, 1, 1, 10, 0, 0);

PuntoGps _punto({
  double lat = 6.2442,
  double lon = -75.5812,
  int segundos = 0,
  double? precision = 5,
}) => PuntoGps(
  latitud: lat,
  longitud: lon,
  capturadoEn: _t0.add(Duration(seconds: segundos)),
  precisionMetros: precision,
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
      // 1 m/s en pasos de 0.00001° (~1.1 m). Umbral 3 m → acepta cada ~3 s.
      calc.agregar(_punto(lat: 6.24420, segundos: 0));
      var aceptados = 0;
      for (var i = 1; i <= 10; i++) {
        final ok = calc.agregar(
          _punto(lat: 6.24420 + i * 0.00001, segundos: i),
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
      final c = CalculadoraDistancia(velocidadMaximaMetrosPorSegundo: 10);
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

    test('con señal buena el umbral es el mínimo de siempre', () {
      // 5-6 m de error es lo normal al aire libre: el umbral adaptativo
      // no se nota.
      expect(calc.umbralPara(5), 3);
      expect(calc.umbralPara(null), 3);
    });

    test('con señal mala hay que moverse más para creerse el movimiento', () {
      // Con 20 m de error, 5 m de "avance" pueden ser solo el error.
      expect(calc.umbralPara(20), 10);
    });

    test('el umbral adaptativo tiene tope', () {
      // Sin tope, una lectura mala dejaría la distancia congelada
      // demasiado tiempo al arrancar de nuevo (SCRUM-116).
      expect(calc.umbralPara(100), 15);
    });

    test('con señal regular el ancla no se va con el jitter', () {
      final c = CalculadoraDistancia();
      // Quieto, con 20 m de error: saltos de ~4.4 m a cada lado.
      c.agregar(_punto(lat: 6.24420, segundos: 0, precision: 20));
      expect(
        c.agregar(_punto(lat: 6.24424, segundos: 1, precision: 20)),
        isFalse,
      );
      expect(
        c.agregar(_punto(lat: 6.24416, segundos: 2, precision: 20)),
        isFalse,
      );

      expect(c.distanciaMetros, 0);
      // El ancla sigue en el punto original: si se hubiera corrido, el
      // siguiente tramo real se mediría desde un sitio equivocado.
      expect(c.ultimoPuntoAceptado!.latitud, 6.24420);
    });

    test('el tramo aceptado guarda distancia e instantes', () {
      calc.agregar(_punto(segundos: 0));
      calc.agregar(_punto(lat: 6.2452, segundos: 30));

      final tramo = calc.ultimoTramo!;
      expect(tramo.metros, closeTo(_metrosPorMiliGrado, 0.5));
      expect(tramo.inicio, _t0);
      expect(tramo.fin, _t0.add(const Duration(seconds: 30)));
      expect(tramo.duracion, const Duration(seconds: 30));
    });

    test('sin tramos aceptados todavía no hay tramo', () {
      calc.agregar(_punto(segundos: 0));

      expect(calc.ultimoTramo, isNull);
    });

    test('parámetros personalizados se respetan', () {
      final c = CalculadoraDistancia(
        precisionMaximaMetros: 100,
        desplazamientoMinimoMetros: 0,
        // Sin esto, una lectura de 80 m de error exigiría el umbral
        // adaptativo completo y no se aceptaría el punto.
        factorRuidoPrecision: 0,
      );
      c.agregar(_punto(segundos: 0, precision: 80));
      expect(
        c.agregar(_punto(lat: 6.24421, segundos: 1, precision: 80)),
        isTrue,
      );
      expect(c.distanciaMetros, greaterThan(0));
    });
  });
}
