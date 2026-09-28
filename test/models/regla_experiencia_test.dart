import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/regla_experiencia.dart';

/// Pruebas de las reglas de XP por actividad (SCRUM-202, SCRUM-209).
void main() {
  ExperienciaActividad calcular(
    double? metros,
    Duration? duracion, {
    double hoy = 0,
  }) => ReglaExperiencia.calcular(
    distanciaMetros: metros,
    duracion: duracion,
    metrosContadosHoy: hoy,
  );

  const media = Duration(minutes: 30);

  group('tarifa', () {
    test('5 km dan 25 XP', () {
      expect(
        calcular(5000, media),
        const ExperienciaActividad(
          xp: 25,
          metrosContados: 5000,
          ajuste: AjusteExperiencia.ninguno,
        ),
      );
    });

    test('solo cuentan los 200 m completos', () {
      expect(calcular(1199, media).xp, 5);
      expect(calcular(1200, media).xp, 6);
      // El ruido del GPS deja decimales: no cambian nada.
      expect(calcular(5003.7, media).xp, 25);
    });

    test('caminar paga lo mismo por km que correr', () {
      // 3 km en 36 min: 5 km/h.
      final caminata = calcular(3000, const Duration(minutes: 36));
      // 3 km en 15 min: 12 km/h.
      final carrera = calcular(3000, const Duration(minutes: 15));

      expect(caminata.xp, 15);
      expect(carrera.xp, caminata.xp);
    });
  });

  group('mínimo de distancia', () {
    test('el primer km completo ya da XP', () {
      expect(calcular(1000, const Duration(minutes: 10)).xp, 5);
    });

    test('menos de 1 km no da XP ni gasta tope', () {
      expect(
        calcular(999, const Duration(minutes: 10)),
        const ExperienciaActividad(
          xp: 0,
          metrosContados: 0,
          ajuste: AjusteExperiencia.menosDelMinimo,
        ),
      );
    });
  });

  group('datos incompletos', () {
    test('sin distancia o con distancia cero no hay XP', () {
      expect(calcular(null, media).ajuste, AjusteExperiencia.sinDatos);
      expect(calcular(0, media).ajuste, AjusteExperiencia.sinDatos);
      expect(calcular(null, media).xp, 0);
    });

    test('sin duración no se puede validar la velocidad', () {
      expect(calcular(5000, null).ajuste, AjusteExperiencia.sinDatos);
      expect(calcular(5000, Duration.zero).ajuste, AjusteExperiencia.sinDatos);
      expect(calcular(5000, null).xp, 0);
    });
  });

  group('velocidad plausible', () {
    test('justo en 25 km/h todavía cuenta', () {
      // 5 km en 12 min.
      expect(calcular(5000, const Duration(minutes: 12)).xp, 25);
    });

    test('por encima de 25 km/h no da XP ni gasta tope', () {
      // 10 km en 20 min: 30 km/h, un carro o una bici.
      expect(
        calcular(10000, const Duration(minutes: 20)),
        const ExperienciaActividad(
          xp: 0,
          metrosContados: 0,
          ajuste: AjusteExperiencia.velocidadImposible,
        ),
      );
    });
  });

  group('tope diario', () {
    test('una tirada larga cuenta hasta 25 km', () {
      // 30 km en 3 h.
      expect(
        calcular(30000, const Duration(hours: 3)),
        const ExperienciaActividad(
          xp: 125,
          metrosContados: 25000,
          ajuste: AjusteExperiencia.topeDiario,
        ),
      );
    });

    test('llegar justo al tope no es recortar', () {
      expect(
        calcular(5000, media, hoy: 20000),
        const ExperienciaActividad(
          xp: 25,
          metrosContados: 5000,
          ajuste: AjusteExperiencia.ninguno,
        ),
      );
    });

    test('solo cuenta lo que queda del tope del día', () {
      expect(
        calcular(8000, const Duration(minutes: 48), hoy: 20000),
        const ExperienciaActividad(
          xp: 25,
          metrosContados: 5000,
          ajuste: AjusteExperiencia.topeDiario,
        ),
      );
    });

    test('el mínimo se mide sobre la actividad, no sobre lo que queda', () {
      // Quedan 100 m del tope: cuentan, pero no alcanzan para 1 XP.
      expect(
        calcular(5000, media, hoy: 24900),
        const ExperienciaActividad(
          xp: 0,
          metrosContados: 100,
          ajuste: AjusteExperiencia.topeDiario,
        ),
      );
    });

    test('con el tope lleno la actividad no da XP', () {
      expect(
        calcular(5000, media, hoy: 25000),
        const ExperienciaActividad(
          xp: 0,
          metrosContados: 0,
          ajuste: AjusteExperiencia.topeDiario,
        ),
      );
    });

    test('partir el día en muchas actividades no pasa del tope', () {
      // Diez actividades de 3 km: 30 km en el día.
      var hoy = 0.0;
      var xp = 0;
      for (var i = 0; i < 10; i++) {
        final resultado = calcular(3000, const Duration(minutes: 18), hoy: hoy);
        hoy += resultado.metrosContados;
        xp += resultado.xp;
      }

      expect(hoy, ReglaExperiencia.topeDiarioMetros);
      expect(xp, 125);
    });
  });
}
