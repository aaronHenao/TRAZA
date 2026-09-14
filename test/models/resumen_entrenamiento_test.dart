import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/resumen_entrenamiento.dart';

/// Pruebas del formato de los datos que muestra el resumen (SCRUM-117).
void main() {
  ResumenEntrenamiento resumen({
    Duration duracion = const Duration(minutes: 32, seconds: 17),
    double? distanciaMetros,
    DateTime? fechaFin,
  }) {
    return ResumenEntrenamiento(
      nombreActividad: 'Trote',
      fechaFin: fechaFin ?? DateTime(2026, 9, 13, 18, 30),
      duracion: duracion,
      distanciaMetros: distanciaMetros,
    );
  }

  group('tiempo', () {
    test('usa el mismo formato HH:MM:SS del cronómetro', () {
      expect(resumen().tiempo, '00:32:17');
      expect(
        resumen(
          duracion: const Duration(hours: 1, minutes: 5, seconds: 9),
        ).tiempo,
        '01:05:09',
      );
    });
  });

  group('distancia', () {
    test('en kilómetros con dos decimales', () {
      expect(resumen(distanciaMetros: 5230.5).distancia, '5.23 km');
      expect(resumen(distanciaMetros: 0).distancia, '0.00 km');
    });

    test('sin distancia calculada muestra que no hay dato', () {
      expect(resumen().distancia, ResumenEntrenamiento.sinDato);
    });
  });

  group('ritmo', () {
    test('en minutos y segundos por kilómetro', () {
      // 1937 s en 5.2305 km: 370.3 s/km.
      expect(resumen(distanciaMetros: 5230.5).ritmo, '6\'10"/km');
    });

    test('redondea sin llegar a 60 segundos', () {
      // 3599 s en 10 km: 359.9 s/km, que es 6'00" y no 5'60".
      expect(
        resumen(
          duracion: const Duration(seconds: 3599),
          distanciaMetros: 10000,
        ).ritmo,
        '6\'00"/km',
      );
    });

    test('sin distancia, o con muy poca, no hay ritmo', () {
      expect(resumen().ritmo, ResumenEntrenamiento.sinDato);
      expect(resumen(distanciaMetros: 0).ritmo, ResumenEntrenamiento.sinDato);
      expect(resumen(distanciaMetros: 4).ritmo, ResumenEntrenamiento.sinDato);
    });
  });

  group('subtítulo', () {
    final ahora = DateTime(2026, 9, 13, 20);

    test('dice "hoy" si terminó el mismo día', () {
      expect(resumen().subtitulo(ahora), 'Trote · hoy');
    });

    test('dice "ayer" si terminó el día anterior, aunque fuera de noche', () {
      final fechaFin = DateTime(2026, 9, 12, 23, 50);
      expect(resumen(fechaFin: fechaFin).subtitulo(ahora), 'Trote · ayer');
    });

    test('muestra la fecha si fue antes', () {
      final fechaFin = DateTime(2026, 9, 3, 7);
      expect(resumen(fechaFin: fechaFin).subtitulo(ahora), 'Trote · 3 sep');
    });

    test('agrega el año si fue otro año', () {
      final fechaFin = DateTime(2025, 12, 31, 7);
      expect(
        resumen(fechaFin: fechaFin).subtitulo(ahora),
        'Trote · 31 dic 2025',
      );
    });
  });
}
