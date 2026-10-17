import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';

/// Qué se puede cambiar de un reto ya publicado (SCRUM-133) y qué no.
void main() {
  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');

  final publicado = Reto(
    id: 'r1',
    nombre: 'Corre 15 km esta semana',
    descripcion: 'Suma 15 km entre lunes y domingo.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: 15,
    xpOtorgada: 200,
    vigencia: VigenciaReto(
      inicio: DateTime(2026, 10, 5),
      fin: DateTime(2026, 10, 11),
    ),
    estado: EstadoReto.activo,
    tipoActividad: correr,
  );

  group('el borrador se llena con el reto que se va a editar', () {
    test('trae lo que el administrador verá en el formulario', () {
      final borrador = BorradorReto.de(publicado);

      expect(borrador.nombre, 'Corre 15 km esta semana');
      expect(borrador.descripcion, 'Suma 15 km entre lunes y domingo.');
      expect(borrador.periodicidad, PeriodicidadReto.semanal);
      expect(borrador.tipoActividad, correr);
      expect(borrador.fin, DateTime(2026, 10, 11));
    });

    test('los números vuelven a texto sin decimales de más', () {
      expect(BorradorReto.de(publicado).meta, '15');
      expect(BorradorReto.de(publicado).xp, '200');
    });

    test('una meta con decimales los conserva', () {
      final conDecimales = Reto(
        id: 'r2',
        nombre: 'Corre 2.5 km',
        descripcion: 'Una vuelta corta.',
        periodicidad: PeriodicidadReto.diaria,
        metaKm: 2.5,
        xpOtorgada: 20,
        vigencia: VigenciaReto(
          inicio: DateTime(2026, 10, 5),
          fin: DateTime(2026, 10, 5),
        ),
        estado: EstadoReto.activo,
        tipoActividad: correr,
      );

      expect(BorradorReto.de(conDecimales).meta, '2.5');
    });

    test('un reto recién cargado se puede guardar tal cual', () {
      // Abrir el formulario y pulsar guardar sin tocar nada no debe
      // reprochar nada: lo que hay publicado ya pasó las reglas.
      expect(BorradorReto.de(publicado).esValido, isTrue);
    });
  });

  group('lo que se manda al guardar', () {
    test('lleva solo las columnas que se pueden cambiar', () {
      final cambios = BorradorReto.de(publicado)
          .copyWith(nombre: 'Corre 20 km esta semana', meta: '20')
          .aCambios(publicado)!;

      expect(cambios.aSupabase(), {
        'nombre': 'Corre 20 km esta semana',
        'descripcion': 'Suma 15 km entre lunes y domingo.',
        'meta_km': 20.0,
        'xp_otorgada': 200,
        'fecha_fin': '2026-10-11',
      });
    });

    test('ni la periodicidad, ni el tipo, ni el inicio, ni el estado', () {
      // Los tres primeros moverían de sitio a quien ya lo tiene activo; el
      // estado es de retirar un reto, no de editarlo.
      final fila = BorradorReto.de(publicado).aCambios(publicado)!.aSupabase();

      for (final columna in [
        'periodicidad',
        'tipo_actividad_id',
        'fecha_inicio',
        'estado',
      ]) {
        expect(fila.containsKey(columna), isFalse, reason: columna);
      }
    });

    test('recorta los espacios sobrantes', () {
      final cambios = BorradorReto.de(
        publicado,
      ).copyWith(nombre: '  Corre 20 km  ').aCambios(publicado)!;

      expect(cambios.nombre, 'Corre 20 km');
    });
  });

  group('la fecha de fin solo se mueve hacia adelante', () {
    test('alargar el plazo se guarda', () {
      final cambios = BorradorReto.de(
        publicado,
      ).copyWith(fin: DateTime(2026, 10, 18)).aCambios(publicado)!;

      expect(cambios.vigencia.fin, DateTime(2026, 10, 18));
      expect(cambios.aSupabase()['fecha_fin'], '2026-10-18');
    });

    test('acortarlo no: se conserva el plazo que había', () {
      // Quien iba cumpliendo el reto no puede quedarse sin tiempo por una
      // edición que no le avisó.
      final cambios = BorradorReto.de(
        publicado,
      ).copyWith(fin: DateTime(2026, 10, 7)).aCambios(publicado)!;

      expect(cambios.vigencia.fin, DateTime(2026, 10, 11));
    });

    test('dejarla igual tampoco la mueve', () {
      final cambios = BorradorReto.de(publicado).aCambios(publicado)!;

      expect(cambios.vigencia, publicado.vigencia);
    });

    test('el inicio nunca se mueve', () {
      final cambios = BorradorReto.de(
        publicado,
      ).copyWith(fin: DateTime(2026, 10, 30)).aCambios(publicado)!;

      expect(cambios.vigencia.inicio, DateTime(2026, 10, 5));
    });
  });

  group('validaciones al editar (criterio 3)', () {
    test('sin nombre no se guarda nada', () {
      final borrador = BorradorReto.de(publicado).copyWith(nombre: '   ');

      expect(borrador.aCambios(publicado), isNull);
      expect(borrador.errores[CampoReto.nombre], isNotNull);
    });

    test('una meta de cero no se guarda', () {
      final borrador = BorradorReto.de(publicado).copyWith(meta: '0');

      expect(borrador.aCambios(publicado), isNull);
      expect(
        borrador.errores[CampoReto.meta],
        'La meta debe ser mayor que cero.',
      );
    });

    test('una XP negativa no se guarda', () {
      final borrador = BorradorReto.de(publicado).copyWith(xp: '-5');

      expect(borrador.aCambios(publicado), isNull);
      expect(borrador.errores[CampoReto.xp], isNotNull);
    });

    test('una meta que no es un número no se guarda', () {
      final borrador = BorradorReto.de(publicado).copyWith(meta: 'cinco');

      expect(borrador.aCambios(publicado), isNull);
    });
  });
}
