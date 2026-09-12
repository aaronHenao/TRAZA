import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/puntos_gps_service.dart';
import 'package:traza/services/ubicacion_service.dart';

import '../utiles/fuente_ubicacion_falsa.dart';

void main() {
  group('RepositorioPuntosGpsSupabase.filaPara', () {
    test('mapea el punto a las columnas de puntos_gps', () {
      final fila = RepositorioPuntosGpsSupabase.filaPara(
        entrenamientoId: 'e-123',
        punto: PuntoGps(
          latitud: 6.2311,
          longitud: -75.6105,
          capturadoEn: DateTime.utc(2026, 9, 12, 21, 30, 15),
          precisionMetros: 8,
        ),
        ordenSecuencia: 7,
      );

      expect(fila, {
        'entrenamiento_id': 'e-123',
        'latitud': 6.2311,
        'longitud': -75.6105,
        'capturado_en': '2026-09-12T21:30:15.000Z',
        'orden_secuencia': 7,
      });
    });

    test('guarda capturado_en en UTC aunque el reloj sea local', () {
      final local = DateTime(2026, 9, 12, 16, 30, 15);
      final fila = RepositorioPuntosGpsSupabase.filaPara(
        entrenamientoId: 'e-123',
        punto: puntoDePrueba(capturadoEn: local),
        ordenSecuencia: 0,
      );

      expect(fila['capturado_en'], local.toUtc().toIso8601String());
      expect(fila['capturado_en'], endsWith('Z'));
    });

    test('filasPara numera orden_secuencia por posicion en la lista', () {
      final filas = RepositorioPuntosGpsSupabase.filasPara(
        entrenamientoId: 'e-123',
        puntos: [
          puntoDePrueba(latitud: 6.2311),
          puntoDePrueba(latitud: 6.2312),
          puntoDePrueba(latitud: 6.2313),
        ],
      );

      expect(filas.map((f) => f['orden_secuencia']), [0, 1, 2]);
      expect(filas.map((f) => f['latitud']), [6.2311, 6.2312, 6.2313]);
      expect(filas.every((f) => f['entrenamiento_id'] == 'e-123'), isTrue);
    });

    test('filasPara con lista vacia devuelve lista vacia', () {
      final filas = RepositorioPuntosGpsSupabase.filasPara(
        entrenamientoId: 'e-123',
        puntos: const [],
      );

      expect(filas, isEmpty);
    });

    test('no incluye altitud', () {
      final fila = RepositorioPuntosGpsSupabase.filaPara(
        entrenamientoId: 'e-123',
        punto: puntoDePrueba(),
        ordenSecuencia: 0,
      );

      expect(fila.keys, isNot(contains('altitud')));
    });
  });

  group('ConfiguracionRastreo', () {
    // Las lecturas de prueba se capturan a las 08:00; "ahora" es lo mismo.
    final ahora = DateTime(2026, 1, 1, 8);

    test('por defecto filtra cada 5 m, precision alta, tope 50 m y 30 s',
        () {
      const config = ConfiguracionRastreo();

      expect(config.distanciaMinimaMetros, 5);
      expect(config.altaPrecision, isTrue);
      expect(config.precisionMaximaMetros, 50);
      expect(config.antiguedadMaxima, const Duration(seconds: 30));
    });

    test('acepta lecturas dentro del tope y rechaza las peores', () {
      const config = ConfiguracionRastreo(precisionMaximaMetros: 50);

      expect(config.acepta(puntoDePrueba(precisionMetros: 8), ahora: ahora),
          isTrue);
      expect(config.acepta(puntoDePrueba(precisionMetros: 50), ahora: ahora),
          isTrue);
      expect(config.acepta(puntoDePrueba(precisionMetros: 51), ahora: ahora),
          isFalse);
      expect(config.acepta(puntoDePrueba(precisionMetros: 200), ahora: ahora),
          isFalse);
    });

    test('sin precision reportada acepta la lectura', () {
      const config = ConfiguracionRastreo(precisionMaximaMetros: 50);

      expect(config.acepta(puntoDePrueba(precisionMetros: null), ahora: ahora),
          isTrue);
    });

    test('sin tope acepta cualquier precision', () {
      const config = ConfiguracionRastreo(precisionMaximaMetros: null);

      expect(config.acepta(puntoDePrueba(precisionMetros: 500), ahora: ahora),
          isTrue);
    });

    test('rechaza la ultima posicion conocida si es vieja', () {
      const config = ConfiguracionRastreo(
        antiguedadMaxima: Duration(seconds: 30),
      );
      final hace5min = puntoDePrueba(
        capturadoEn: ahora.subtract(const Duration(minutes: 5)),
      );
      final hace20s = puntoDePrueba(
        capturadoEn: ahora.subtract(const Duration(seconds: 20)),
      );

      expect(config.acepta(hace5min, ahora: ahora), isFalse);
      expect(config.acepta(hace20s, ahora: ahora), isTrue);
    });

    test('una marca de tiempo en el futuro no cuenta como vieja', () {
      const config = ConfiguracionRastreo();
      final adelantada = puntoDePrueba(
        capturadoEn: ahora.add(const Duration(minutes: 2)),
      );

      expect(config.acepta(adelantada, ahora: ahora), isTrue);
    });

    test('sin tope de antiguedad acepta lecturas viejas', () {
      const config = ConfiguracionRastreo(antiguedadMaxima: null);
      final vieja = puntoDePrueba(
        capturadoEn: ahora.subtract(const Duration(hours: 1)),
      );

      expect(config.acepta(vieja, ahora: ahora), isTrue);
    });
  });
}
