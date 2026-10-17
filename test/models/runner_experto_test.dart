import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/runner_experto.dart';

/// Un mapa de [cantidad] niveles, el primero en [paso] XP y cada uno [paso]
/// más arriba que el anterior.
List<Nivel> _mapa(int cantidad, {int paso = 100}) => [
  for (var i = 1; i <= cantidad; i++)
    Nivel(id: 'n$i', nombre: 'Etapa $i', umbralExperiencia: i * paso),
];

/// El estado frente a Runner Experto (SCRUM-211, SCRUM-214): cuánto falta en
/// cada requisito y cuándo queda desbloqueado (SCRUM-216).
void main() {
  // Registrado hace más de seis meses: la antigüedad no estorba cuando se
  // prueba la XP.
  final antiguo = DateTime(2025, 1, 10, 9);
  final hoy = DateTime(2026, 9, 28, 18);

  // Once niveles que se alcanzan con 1.100 XP: los niveles no estorban cuando
  // se prueba la XP.
  final faciles = _mapa(11);

  EstadoRunnerExperto conXp(int experiencia) => EstadoRunnerExperto.calcular(
    experiencia: experiencia,
    niveles: faciles,
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
          niveles: faciles,
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

  group('niveles del mapa (SCRUM-227)', () {
    // Umbrales de 20.000 en 20.000: el undécimo nivel está en 220.000, por
    // encima de la XP que se pide, así que la XP no basta para cumplirlo.
    final exigentes = _mapa(11, paso: 20000);

    EstadoRunnerExperto conNiveles(int experiencia, List<Nivel> niveles) =>
        EstadoRunnerExperto.calcular(
          experiencia: experiencia,
          niveles: niveles,
          fechaRegistro: antiguo,
          ahora: hoy,
        );

    test('el requisito es superar el décimo nivel: alcanzar 11', () {
      expect(RequisitosRunnerExperto.nivelesAlcanzados, 11);
    });

    test('sin ningún nivel alcanzado le faltan todos', () {
      final estado = conNiveles(50, faciles);

      expect(estado.nivelesAlcanzados, 0);
      expect(estado.nivelActual, isNull);
      expect(estado.nivelesFaltantes, 11);
      expect(estado.avanceNiveles, 0);
      expect(estado.cumpleNiveles, isFalse);
    });

    test('a mitad de camino dice en qué nivel va y cuántos faltan', () {
      final estado = conNiveles(450, faciles);

      expect(estado.nivelesAlcanzados, 4);
      expect(estado.nivelActual?.nombre, 'Etapa 4');
      expect(estado.nivelesFaltantes, 7);
      expect(estado.avanceNiveles, closeTo(4 / 11, 0.0001));
    });

    test('en el nivel 10 todavía no lo supera, aunque tenga la XP', () {
      final estado = conNiveles(200000, exigentes);

      expect(estado.nivelesAlcanzados, 10);
      expect(estado.nivelesFaltantes, 1);
      expect(estado.cumpleExperiencia, isTrue);
      expect(estado.cumpleNiveles, isFalse);
      expect(estado.desbloqueado, isFalse);
    });

    test('con el umbral exacto del undécimo ya lo cumple', () {
      final estado = conNiveles(220000, exigentes);

      expect(estado.nivelesAlcanzados, 11);
      expect(estado.nivelesFaltantes, 0);
      expect(estado.avanceNiveles, 1);
      expect(estado.cumpleNiveles, isTrue);
      expect(estado.desbloqueado, isTrue);
    });

    test('los niveles de sobra no pasan la barra de llena', () {
      final estado = conNiveles(150000, _mapa(15));

      expect(estado.nivelesAlcanzados, 15);
      expect(estado.nivelActual?.nombre, 'Etapa 15');
      expect(estado.nivelesFaltantes, 0);
      expect(estado.avanceNiveles, 1);
    });

    test('el orden en que lleguen los niveles no cambia la cuenta', () {
      final estado = conNiveles(450, faciles.reversed.toList());

      expect(estado.nivelesAlcanzados, 4);
      expect(estado.nivelActual?.nombre, 'Etapa 4');
    });

    test('si el mapa tiene menos de 11 niveles no lo puede cumplir', () {
      final estado = conNiveles(150000, _mapa(8));

      expect(estado.nivelesAlcanzados, 8);
      expect(estado.nivelesEnMapa, 8);
      expect(estado.faltanNivelesEnMapa, isTrue);
      expect(estado.cumpleNiveles, isFalse);
      expect(estado.desbloqueado, isFalse);
    });

    test('con el mapa completo no avisa que faltan niveles', () {
      expect(conNiveles(0, faciles).faltanNivelesEnMapa, isFalse);
    });
  });

  test('solo queda desbloqueado con los tres requisitos', () {
    final reciente = DateTime(2026, 9, 1);
    EstadoRunnerExperto estado({
      required int experiencia,
      required List<Nivel> niveles,
      required DateTime registro,
    }) => EstadoRunnerExperto.calcular(
      experiencia: experiencia,
      niveles: niveles,
      fechaRegistro: registro,
      ahora: hoy,
    );

    final sinNinguno = estado(
      experiencia: 10,
      niveles: faciles,
      registro: reciente,
    );
    final soloXpYNiveles = estado(
      experiencia: 200000,
      niveles: faciles,
      registro: reciente,
    );
    final soloAntiguedad = conXp(10);
    final sinNiveles = estado(
      experiencia: 200000,
      niveles: _mapa(10),
      registro: antiguo,
    );
    final losTres = conXp(200000);

    expect(sinNinguno.desbloqueado, isFalse);
    expect(soloXpYNiveles.desbloqueado, isFalse);
    expect(soloAntiguedad.desbloqueado, isFalse);
    expect(sinNiveles.desbloqueado, isFalse);
    expect(losTres.desbloqueado, isTrue);
  });

  test('las ventajas son evaluar rutas y la insignia', () {
    expect(VentajaRunnerExperto.values, [
      VentajaRunnerExperto.evaluarRutas,
      VentajaRunnerExperto.insignia,
    ]);
  });
}
