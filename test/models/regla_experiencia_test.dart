import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/regla_experiencia.dart';

/// Pruebas de la regla que decide si un entrenamiento cuenta para los retos
/// (SCRUM-202, SCRUM-209).
void main() {
  AjusteExperiencia evaluar(double? metros, Duration? duracion) =>
      ReglaExperiencia.evaluar(distanciaMetros: metros, duracion: duracion);

  const media = Duration(minutes: 30);

  group('cuenta para los retos', () {
    test('una carrera normal cuenta entera', () {
      expect(evaluar(5000, media), AjusteExperiencia.ninguno);
    });

    test('menos de 1 km también cuenta: ya no hay mínimo', () {
      expect(
        evaluar(300, const Duration(minutes: 3)),
        AjusteExperiencia.ninguno,
      );
    });

    test('una tirada larga cuenta entera: ya no hay tope diario', () {
      // 42 km en 4 h.
      expect(
        evaluar(42000, const Duration(hours: 4)),
        AjusteExperiencia.ninguno,
      );
    });

    test('caminar cuenta igual que correr', () {
      // 3 km en 36 min: 5 km/h.
      expect(
        evaluar(3000, const Duration(minutes: 36)),
        AjusteExperiencia.ninguno,
      );
    });
  });

  group('datos incompletos', () {
    test('sin distancia o con distancia cero no cuenta', () {
      expect(evaluar(null, media), AjusteExperiencia.sinDatos);
      expect(evaluar(0, media), AjusteExperiencia.sinDatos);
    });

    test('sin duración no se puede validar la velocidad', () {
      expect(evaluar(5000, null), AjusteExperiencia.sinDatos);
      expect(evaluar(5000, Duration.zero), AjusteExperiencia.sinDatos);
    });
  });

  group('velocidad plausible', () {
    test('justo en 25 km/h todavía cuenta', () {
      // 5 km en 12 min.
      expect(
        evaluar(5000, const Duration(minutes: 12)),
        AjusteExperiencia.ninguno,
      );
    });

    test('por encima de 25 km/h no cuenta', () {
      // 10 km en 20 min: 30 km/h, un carro o una bici.
      expect(
        evaluar(10000, const Duration(minutes: 20)),
        AjusteExperiencia.velocidadImposible,
      );
    });
  });
}
