import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';

/// Pruebas de la dificultad de una ruta (SCRUM-275).
void main() {
  test('son los tres niveles de HU-36, de la más fácil a la más difícil', () {
    expect(
      [for (final dificultad in Dificultad.values) dificultad.etiqueta],
      ['Fácil', 'Moderada', 'Difícil'],
    );
    expect(
      [for (final dificultad in Dificultad.values) dificultad.plural],
      ['fáciles', 'moderadas', 'difíciles'],
    );
  });

  group('en la base', () {
    test('se guarda con un valor sin tildes ni mayúsculas', () {
      expect(
        [for (final dificultad in Dificultad.values) dificultad.valorDb],
        ['facil', 'moderada', 'dificil'],
      );
      for (final dificultad in Dificultad.values) {
        expect(Dificultad.desdeDb(dificultad.valorDb), dificultad);
      }
    });

    test('sin valor, la ruta está sin clasificar', () {
      expect(Dificultad.desdeDb(null), isNull);
    });

    test('un valor que no se conoce se lee como sin clasificar', () {
      expect(Dificultad.desdeDb('Fácil'), isNull);
      expect(Dificultad.desdeDb('extrema'), isNull);
      expect(Dificultad.desdeDb(2), isNull);
    });
  });

  group('en una fila de rutas', () {
    Map<String, Object?> fila({Object? dificultad}) => {
      'id': 'ruta-1',
      'autor_id': 'autor-1',
      'autor_nombre': 'Ana',
      'nombre': 'Subida al Nutibara',
      'estado': 'publicada',
      'fecha_creacion': '2026-10-18T14:00:00Z',
      'dificultad': ?dificultad,
    };

    test('la ruta trae la que tenga', () {
      expect(
        Ruta.desdeSupabase(fila(dificultad: 'moderada')).dificultad,
        Dificultad.moderada,
      );
    });

    test('las consultas de hoy no la traen: la ruta queda sin clasificar', () {
      // `rutas.dificultad` la crea SCRUM-363.
      expect(Ruta.desdeSupabase(fila()).dificultad, isNull);
    });
  });

  group('cuándo la revisó un Runner Experto (SCRUM-264)', () {
    Map<String, Object?> fila({Object? revisadaEn}) => {
      'id': 'ruta-1',
      'autor_id': 'autor-1',
      'autor_nombre': 'Ana',
      'nombre': 'Subida al Nutibara',
      'estado': 'publicada',
      'fecha_creacion': '2026-10-18T14:00:00Z',
      'dificultad': 'moderada',
      'dificultad_revisada_en': ?revisadaEn,
    };

    test('la ruta trae cuándo se revisó, en la hora local', () {
      final ruta = Ruta.desdeSupabase(fila(revisadaEn: '2026-10-20T15:30:00Z'));

      expect(
        ruta.dificultadRevisadaEn,
        DateTime.utc(2026, 10, 20, 15, 30).toLocal(),
      );
      expect(ruta.dificultadRevisada, isTrue);
    });

    test('las consultas de hoy no lo traen: no está revisada', () {
      final ruta = Ruta.desdeSupabase(fila());

      expect(ruta.dificultadRevisadaEn, isNull);
      expect(ruta.dificultadRevisada, isFalse);
    });

    test('una fecha que no se entiende se toma como que no está', () {
      expect(
        Ruta.desdeSupabase(fila(revisadaEn: 'ayer')).dificultadRevisada,
        isFalse,
      );
      expect(
        Ruta.desdeSupabase(fila(revisadaEn: 42)).dificultadRevisada,
        isFalse,
      );
    });
  });
}
