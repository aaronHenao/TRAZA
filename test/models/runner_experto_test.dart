import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/runner_experto.dart';

/// El estado frente a Runner Experto (SCRUM-211, SCRUM-214): cuánto falta en
/// cada requisito y cuándo queda desbloqueado (SCRUM-216).
void main() {
  // Registrado hace más de seis meses: la antigüedad no estorba cuando se
  // prueba la XP.
  final antiguo = DateTime(2025, 1, 10, 9);
  final hoy = DateTime(2026, 9, 28, 18);

  EstadoRunnerExperto conXp(int experiencia) => EstadoRunnerExperto.calcular(
    experiencia: experiencia,
    fechaRegistro: antiguo,
    ahora: hoy,
  );

  group('experiencia', () {
    test('muy por debajo: bloqueado y con todo lo que falta', () {
      final estado = conXp(1200);

      expect(estado.cumpleExperiencia, isFalse);
      expect(estado.desbloqueado, isFalse);
      expect(estado.experienciaFaltante, 148800);
      expect(estado.avanceExperiencia, closeTo(0.008, 0.0001));
    });

    test('a un paso: le falta 1 XP y sigue bloqueado', () {
      final estado = conXp(149999);

      expect(estado.cumpleExperiencia, isFalse);
      expect(estado.desbloqueado, isFalse);
      expect(estado.experienciaFaltante, 1);
    });

    test('con la XP exacta ya la cumple', () {
      final estado = conXp(RequisitosRunnerExperto.experiencia);

      expect(estado.cumpleExperiencia, isTrue);
      expect(estado.experienciaFaltante, 0);
      expect(estado.avanceExperiencia, 1);
      expect(estado.desbloqueado, isTrue);
    });

    test('por encima no falta nada negativo ni se pasa de la barra', () {
      final estado = conXp(400000);

      expect(estado.experienciaFaltante, 0);
      expect(estado.avanceExperiencia, 1);
      expect(estado.desbloqueado, isTrue);
    });

    test('sin XP la barra está vacía', () {
      expect(conXp(0).avanceExperiencia, 0);
    });
  });

  group('antigüedad', () {
    EstadoRunnerExperto registrado(DateTime fecha, {DateTime? ahora}) =>
        EstadoRunnerExperto.calcular(
          experiencia: RequisitosRunnerExperto.experiencia,
          fechaRegistro: fecha,
          ahora: ahora ?? hoy,
        );

    test('recién registrado: le faltan los seis meses', () {
      final estado = registrado(DateTime(2026, 9, 28, 7));

      expect(estado.cumpleAntiguedad, isFalse);
      expect(estado.cumpleAntiguedadEl, DateTime(2027, 3, 28));
      expect(estado.diasFaltantes, 181);
      expect(estado.avanceAntiguedad, 0);
      // Con la XP de sobra, la antigüedad sola lo deja bloqueado.
      expect(estado.desbloqueado, isFalse);
    });

    test('a un día de cumplirla', () {
      final estado = registrado(DateTime(2026, 3, 29, 23, 50));

      expect(estado.cumpleAntiguedad, isFalse);
      expect(estado.diasFaltantes, 1);
    });

    test(
      'el mismo día que cumple seis meses ya la cumple, a cualquier hora',
      () {
        final estado = registrado(
          DateTime(2026, 3, 28, 23, 59),
          ahora: DateTime(2026, 9, 28, 0, 1),
        );

        expect(estado.cumpleAntiguedad, isTrue);
        expect(estado.diasFaltantes, 0);
        expect(estado.avanceAntiguedad, 1);
        expect(estado.desbloqueado, isTrue);
      },
    );

    test(
      'si el día no existe seis meses después, cuenta el último del mes',
      () {
        final estado = registrado(
          DateTime(2026, 8, 31),
          ahora: DateTime(2026, 9),
        );

        expect(estado.cumpleAntiguedadEl, DateTime(2027, 2, 28));
      },
    );

    test('cruzar el año no la desordena', () {
      final estado = registrado(
        DateTime(2026, 11, 15),
        ahora: DateTime(2026, 12),
      );

      expect(estado.cumpleAntiguedadEl, DateTime(2027, 5, 15));
    });

    test('a mitad de camino la barra va por la mitad', () {
      final estado = registrado(
        DateTime(2026, 1, 1),
        ahora: DateTime(2026, 4, 1, 12),
      );

      // 90 de 181 días.
      expect(estado.avanceAntiguedad, closeTo(90 / 181, 0.0001));
    });
  });

  test('solo queda desbloqueado con los dos requisitos', () {
    final sinNinguno = EstadoRunnerExperto.calcular(
      experiencia: 10,
      fechaRegistro: DateTime(2026, 9, 1),
      ahora: hoy,
    );
    final soloXp = EstadoRunnerExperto.calcular(
      experiencia: 200000,
      fechaRegistro: DateTime(2026, 9, 1),
      ahora: hoy,
    );
    final soloAntiguedad = conXp(10);
    final ambos = conXp(200000);

    expect(sinNinguno.desbloqueado, isFalse);
    expect(soloXp.desbloqueado, isFalse);
    expect(soloAntiguedad.desbloqueado, isFalse);
    expect(ambos.desbloqueado, isTrue);
  });

  test('las ventajas son evaluar rutas y la insignia', () {
    expect(VentajaRunnerExperto.values, [
      VentajaRunnerExperto.evaluarRutas,
      VentajaRunnerExperto.insignia,
    ]);
  });
}
