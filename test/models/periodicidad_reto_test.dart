import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/vigencia_reto.dart';

/// Pruebas del cálculo automático de vigencia (SCRUM-142): al registrar un
/// reto, la fecha de inicio y la de fin salen de su periodicidad, sin que el
/// administrador las escriba.
void main() {
  group('valores de la base', () {
    test('coinciden con la restricción de la tabla retos', () {
      expect(PeriodicidadReto.diaria.valorDb, 'diaria');
      expect(PeriodicidadReto.semanal.valorDb, 'semanal');
      expect(PeriodicidadReto.mensual.valorDb, 'mensual');
    });

    test('se leen de vuelta desde lo que devuelve Supabase', () {
      expect(PeriodicidadReto.desdeDb('semanal'), PeriodicidadReto.semanal);
      expect(PeriodicidadReto.desdeDb('mensual'), PeriodicidadReto.mensual);
    });

    test('un valor desconocido o nulo no revienta', () {
      expect(PeriodicidadReto.desdeDb('anual'), isNull);
      expect(PeriodicidadReto.desdeDb(null), isNull);
    });
  });

  group('reto diario', () {
    test('empieza y termina hoy', () {
      // Martes 22 de septiembre, a media tarde.
      final vigencia = PeriodicidadReto.diaria.vigenciaDesde(
        DateTime(2026, 9, 22, 15, 40),
      );

      expect(vigencia.inicio, DateTime(2026, 9, 22));
      expect(vigencia.fin, DateTime(2026, 9, 22));
      expect(vigencia.dias, 1);
    });

    test('la hora de creación no se cuela en las fechas', () {
      final casiMedianoche = PeriodicidadReto.diaria.vigenciaDesde(
        DateTime(2026, 9, 22, 23, 59, 59),
      );

      expect(casiMedianoche.inicio, DateTime(2026, 9, 22));
      expect(casiMedianoche.fin, DateTime(2026, 9, 22));
    });
  });

  group('reto semanal', () {
    test('va del lunes al domingo de la semana en curso', () {
      // Miércoles 23 de septiembre de 2026.
      final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
        DateTime(2026, 9, 23, 10),
      );

      expect(vigencia.inicio, DateTime(2026, 9, 21)); // lunes
      expect(vigencia.fin, DateTime(2026, 9, 27)); // domingo
      expect(vigencia.dias, 7);
    });

    test('creado un lunes, empieza ese mismo día', () {
      final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
        DateTime(2026, 9, 21, 6),
      );

      expect(vigencia.inicio, DateTime(2026, 9, 21));
      expect(vigencia.fin, DateTime(2026, 9, 27));
    });

    test('creado un domingo, sigue siendo la semana que empezó el lunes', () {
      final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
        DateTime(2026, 9, 27, 22),
      );

      expect(vigencia.inicio, DateTime(2026, 9, 21));
      expect(vigencia.fin, DateTime(2026, 9, 27));
    });

    test('la semana puede cruzar el cambio de mes', () {
      // Miércoles 30 de septiembre: la semana termina en octubre.
      final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
        DateTime(2026, 9, 30),
      );

      expect(vigencia.inicio, DateTime(2026, 9, 28));
      expect(vigencia.fin, DateTime(2026, 10, 4));
      expect(vigencia.dias, 7);
    });

    test('y también el cambio de año', () {
      // Viernes 1 de enero de 2027: la semana empezó el lunes 28 de
      // diciembre de 2026.
      final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
        DateTime(2027, 1, 1),
      );

      expect(vigencia.inicio, DateTime(2026, 12, 28));
      expect(vigencia.fin, DateTime(2027, 1, 3));
    });
  });

  group('reto mensual', () {
    test('va del día 1 al último del mes', () {
      final vigencia = PeriodicidadReto.mensual.vigenciaDesde(
        DateTime(2026, 9, 22),
      );

      expect(vigencia.inicio, DateTime(2026, 9, 1));
      expect(vigencia.fin, DateTime(2026, 9, 30));
      expect(vigencia.dias, 30);
    });

    test('respeta los meses de 31 días', () {
      final vigencia = PeriodicidadReto.mensual.vigenciaDesde(
        DateTime(2026, 10, 15),
      );

      expect(vigencia.fin, DateTime(2026, 10, 31));
      expect(vigencia.dias, 31);
    });

    test('diciembre termina el 31, sin irse al año siguiente', () {
      final vigencia = PeriodicidadReto.mensual.vigenciaDesde(
        DateTime(2026, 12, 5),
      );

      expect(vigencia.inicio, DateTime(2026, 12, 1));
      expect(vigencia.fin, DateTime(2026, 12, 31));
    });

    test('febrero de un año normal termina el 28', () {
      final vigencia = PeriodicidadReto.mensual.vigenciaDesde(
        DateTime(2026, 2, 10),
      );

      expect(vigencia.fin, DateTime(2026, 2, 28));
      expect(vigencia.dias, 28);
    });

    test('y el de un año bisiesto, el 29', () {
      // 2028 es bisiesto.
      final vigencia = PeriodicidadReto.mensual.vigenciaDesde(
        DateTime(2028, 2, 10),
      );

      expect(vigencia.fin, DateTime(2028, 2, 29));
      expect(vigencia.dias, 29);
    });
  });

  group('la vigencia como dato', () {
    final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
      DateTime(2026, 9, 23),
    );

    test('se escribe como la espera una columna date de Postgres', () {
      expect(vigencia.inicioTexto, '2026-09-21');
      expect(vigencia.finTexto, '2026-09-27');
    });

    test('los meses y días de una cifra llevan cero delante', () {
      final enero = PeriodicidadReto.diaria.vigenciaDesde(DateTime(2027, 1, 5));

      expect(enero.inicioTexto, '2027-01-05');
    });

    test('se vuelve a leer de lo que devuelve Supabase', () {
      expect(VigenciaReto.desdeTexto('2026-09-21'), DateTime(2026, 9, 21));
    });

    test('sabe qué días cubre, contando los extremos', () {
      expect(vigencia.cubre(DateTime(2026, 9, 21)), isTrue);
      expect(vigencia.cubre(DateTime(2026, 9, 24, 18)), isTrue);
      expect(vigencia.cubre(DateTime(2026, 9, 27, 23, 59)), isTrue);
      expect(vigencia.cubre(DateTime(2026, 9, 20)), isFalse);
      expect(vigencia.cubre(DateTime(2026, 9, 28)), isFalse);
    });

    test('dos vigencias con las mismas fechas son la misma', () {
      expect(
        PeriodicidadReto.diaria.vigenciaDesde(DateTime(2026, 9, 22, 8)),
        PeriodicidadReto.diaria.vigenciaDesde(DateTime(2026, 9, 22, 20)),
      );
    });
  });

  group('extender la vigencia', () {
    final vigencia = PeriodicidadReto.semanal.vigenciaDesde(
      DateTime(2026, 9, 23),
    );

    test('mover el fin hacia adelante conserva el inicio', () {
      final extendida = vigencia.extendidaHasta(DateTime(2026, 10, 4));

      expect(extendida!.inicio, DateTime(2026, 9, 21));
      expect(extendida.fin, DateTime(2026, 10, 4));
    });

    test('acortarla no se permite: dejaría fuera a quien iba cumpliendo', () {
      expect(vigencia.extendidaHasta(DateTime(2026, 9, 24)), isNull);
    });

    test('dejarla igual tampoco es extenderla', () {
      expect(vigencia.extendidaHasta(DateTime(2026, 9, 27)), isNull);
    });
  });
}
