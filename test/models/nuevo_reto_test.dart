import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';

/// Pruebas de las reglas que impiden registrar un reto incompleto o inválido
/// (SCRUM-141) y del criterio 2 de SCRUM-132: señalar los campos que hay que
/// corregir.
void main() {
  // Miércoles 23 de septiembre de 2026.
  final ahora = DateTime(2026, 9, 23, 11, 30);

  const completo = BorradorReto(
    nombre: 'Corre 5 km hoy',
    descripcion: 'Una sola sesión de carrera de al menos 5 km.',
    periodicidad: PeriodicidadReto.diaria,
    meta: '5',
    xp: '50',
  );

  group('borrador completo', () {
    test('no tiene errores y se puede registrar', () {
      expect(completo.errores, isEmpty);
      expect(completo.esValido, isTrue);
      expect(completo.aNuevoReto(ahora: ahora), isNotNull);
    });

    test('la vigencia se calcula sola a partir de la periodicidad', () {
      final reto = const BorradorReto(
        nombre: 'Corre 15 km esta semana',
        descripcion: 'Suma 15 km entre lunes y domingo.',
        periodicidad: PeriodicidadReto.semanal,
        meta: '15',
        xp: '200',
      ).aNuevoReto(ahora: ahora)!;

      expect(reto.vigencia.inicio, DateTime(2026, 9, 21));
      expect(reto.vigencia.fin, DateTime(2026, 9, 27));
    });

    test('recorta los espacios sobrantes del texto', () {
      final reto = completo
          .copyWith(nombre: '  Corre 5 km hoy  ', descripcion: '  Hazlo.  ')
          .aNuevoReto(ahora: ahora)!;

      expect(reto.nombre, 'Corre 5 km hoy');
      expect(reto.descripcion, 'Hazlo.');
    });
  });

  group('campos obligatorios', () {
    test('el borrador vacío señala los cinco campos', () {
      const vacio = BorradorReto();

      expect(vacio.errores.keys, {
        CampoReto.nombre,
        CampoReto.descripcion,
        CampoReto.periodicidad,
        CampoReto.meta,
        CampoReto.xp,
      });
      expect(vacio.esValido, isFalse);
    });

    test('sin nombre no se registra', () {
      final sinNombre = completo.copyWith(nombre: '');

      expect(sinNombre.errores.keys, {CampoReto.nombre});
      expect(sinNombre.aNuevoReto(ahora: ahora), isNull);
    });

    test('un nombre de solo espacios tampoco es un nombre', () {
      expect(completo.copyWith(nombre: '   ').errores, contains(CampoReto.nombre));
    });

    test('sin descripción no se registra', () {
      expect(
        completo.copyWith(descripcion: '  ').errores.keys,
        {CampoReto.descripcion},
      );
    });

    test('sin periodicidad no se registra: sin ella no hay vigencia', () {
      const sinPeriodicidad = BorradorReto(
        nombre: 'Corre 5 km hoy',
        descripcion: 'Una sesión.',
        meta: '5',
        xp: '50',
      );

      expect(sinPeriodicidad.errores.keys, {CampoReto.periodicidad});
      expect(sinPeriodicidad.aNuevoReto(ahora: ahora), isNull);
    });

    test('el nombre no puede pasarse de largo', () {
      final largo = completo.copyWith(nombre: 'a' * 61);

      expect(largo.errores[CampoReto.nombre], contains('60'));
      expect(completo.copyWith(nombre: 'a' * 60).errores, isEmpty);
    });
  });

  group('meta y XP mayores que cero', () {
    test('una meta en cero no sirve', () {
      final cero = completo.copyWith(meta: '0');

      expect(cero.errores[CampoReto.meta], 'La meta debe ser mayor que cero.');
      expect(cero.aNuevoReto(ahora: ahora), isNull);
    });

    test('una meta negativa tampoco', () {
      expect(completo.copyWith(meta: '-3').errores, contains(CampoReto.meta));
    });

    test('una XP en cero no sirve', () {
      final cero = completo.copyWith(xp: '0');

      expect(cero.errores[CampoReto.xp], 'La XP debe ser mayor que cero.');
      expect(cero.aNuevoReto(ahora: ahora), isNull);
    });

    test('una XP negativa tampoco', () {
      expect(completo.copyWith(xp: '-50').errores, contains(CampoReto.xp));
    });

    test('lo que no es un número se distingue de lo que falta', () {
      expect(
        completo.copyWith(meta: 'cinco').errores[CampoReto.meta],
        'Ingresa un número válido.',
      );
      expect(
        completo.copyWith(meta: '').errores[CampoReto.meta],
        'Indica la meta en kilómetros.',
      );
    });

    test('la XP no admite decimales', () {
      expect(
        completo.copyWith(xp: '50.5').errores[CampoReto.xp],
        'Usa solo números enteros.',
      );
    });

    test('la meta sí, con coma o con punto', () {
      expect(completo.copyWith(meta: '2.5').metaKm, 2.5);
      expect(completo.copyWith(meta: '2,5').metaKm, 2.5);
      expect(completo.copyWith(meta: '2,5').errores, isEmpty);
    });
  });

  group('lo que se manda a Supabase', () {
    test('lleva las columnas de la tabla retos', () {
      final fila = const BorradorReto(
        nombre: 'Mes de 60 km',
        descripcion: 'Acumula 60 km durante el mes.',
        periodicidad: PeriodicidadReto.mensual,
        meta: '60',
        xp: '800',
      ).aNuevoReto(ahora: ahora)!.aSupabase();

      expect(fila, {
        'nombre': 'Mes de 60 km',
        'descripcion': 'Acumula 60 km durante el mes.',
        'periodicidad': 'mensual',
        'meta_km': 60.0,
        'xp_otorgada': 800,
        'fecha_inicio': '2026-09-01',
        'fecha_fin': '2026-09-30',
      });
    });

    test('no manda el estado: lo pone el default de la tabla (SCRUM-145)', () {
      final fila = completo.aNuevoReto(ahora: ahora)!.aSupabase();

      expect(fila.containsKey('estado'), isFalse);
    });

    test('las fechas van como las espera una columna date', () {
      final fila = completo.aNuevoReto(ahora: ahora)!.aSupabase();

      expect(fila['fecha_inicio'], '2026-09-23');
      expect(fila['fecha_fin'], '2026-09-23');
    });
  });
}
