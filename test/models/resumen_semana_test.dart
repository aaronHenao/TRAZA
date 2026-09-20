import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/resumen_semana.dart';

/// Pruebas del resumen semanal que la portada muestra sobre el objetivo del
/// perfil.
void main() {
  // Miércoles: la semana empezó el lunes 14.
  final miercoles = DateTime(2026, 9, 16, 10);

  ResumenEntrenamiento entrenamiento(DateTime fechaFin, {double? metros}) =>
      ResumenEntrenamiento(
        entrenamientoId: 'e-${fechaFin.millisecondsSinceEpoch}',
        nombreActividad: 'Correr',
        fechaFin: fechaFin,
        duracion: const Duration(minutes: 30),
        distanciaMetros: metros,
      );

  group('inicio de semana', () {
    test('es el lunes a las 00:00', () {
      expect(
        ResumenSemana.inicioDeSemana(miercoles),
        DateTime(2026, 9, 14),
      );
    });

    test('el propio lunes empieza ese mismo día', () {
      expect(
        ResumenSemana.inicioDeSemana(DateTime(2026, 9, 14, 23, 59)),
        DateTime(2026, 9, 14),
      );
    });

    test('el domingo sigue perteneciendo a la semana que empezó el lunes', () {
      expect(
        ResumenSemana.inicioDeSemana(DateTime(2026, 9, 20, 22)),
        DateTime(2026, 9, 14),
      );
    });
  });

  group('suma de la semana', () {
    test('solo cuenta los entrenamientos desde el lunes', () {
      final resumen = ResumenSemana.desde([
        entrenamiento(DateTime(2026, 9, 16, 7), metros: 5000),
        entrenamiento(DateTime(2026, 9, 14, 6), metros: 3000),
        // Domingo anterior: fuera de la semana.
        entrenamiento(DateTime(2026, 9, 13, 18), metros: 9000),
      ], ahora: miercoles);

      expect(resumen.entrenamientos, 2);
      expect(resumen.distanciaMetros, 8000);
      expect(resumen.kilometros, 8);
    });

    test('los entrenamientos sin distancia cuentan pero no suman metros', () {
      final resumen = ResumenSemana.desde([
        entrenamiento(DateTime(2026, 9, 16, 7)),
        entrenamiento(DateTime(2026, 9, 15, 7), metros: 2500),
      ], ahora: miercoles);

      expect(resumen.entrenamientos, 2);
      expect(resumen.distanciaMetros, 2500);
    });

    test('sin entrenamientos la semana queda vacía', () {
      final resumen = ResumenSemana.desde([], ahora: miercoles);

      expect(resumen.vacia, isTrue);
      expect(resumen.distanciaMetros, 0);
    });
  });

  group('avance contra el objetivo', () {
    test('sin meta no hay progreso y el texto son solo los kilómetros', () {
      const resumen = ResumenSemana(entrenamientos: 2, distanciaMetros: 9150);

      expect(resumen.progreso, isNull);
      expect(resumen.avanceTexto, '9.2 km');
    });

    test('con meta muestra lo recorrido sobre ella', () {
      const resumen = ResumenSemana(
        entrenamientos: 2,
        distanciaMetros: 9150,
        metaKilometros: 15,
      );

      expect(resumen.progreso, closeTo(0.61, 0.001));
      expect(resumen.avanceTexto, '9.2 / 15 km');
    });

    test('la meta con decimales los conserva', () {
      const resumen = ResumenSemana(
        entrenamientos: 1,
        distanciaMetros: 1000,
        metaKilometros: 7.5,
      );

      expect(resumen.avanceTexto, '1.0 / 7.5 km');
    });

    test('pasarse de la meta llena la barra, no la desborda', () {
      const resumen = ResumenSemana(
        entrenamientos: 4,
        distanciaMetros: 30000,
        metaKilometros: 10,
      );

      expect(resumen.progreso, 1);
    });

    test('una meta en cero no es una meta', () {
      const resumen = ResumenSemana(
        entrenamientos: 0,
        distanciaMetros: 0,
        metaKilometros: 0,
      );

      expect(resumen.progreso, isNull);
    });
  });
}
