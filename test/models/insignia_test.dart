import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/insignia.dart';

/// Pruebas del modelo de insignia (SCRUM-193).
///
/// Quién otorga la insignia es el trigger de la base; el modelo solo lee la
/// fila del catálogo con la obtención del usuario embebida.
void main() {
  group('Insignia.desdeSupabase', () {
    test('lee una insignia obtenida con su fecha de obtención', () {
      final insignia = Insignia.desdeSupabase(const {
        'id': 'i-1',
        'nombre': 'Primera huella',
        'descripcion': 'Tu primer kilómetro con TRAZA',
        'icono': 'huella',
        'xp_requerida': 5,
        'insignias_usuario': [
          {'fecha_obtencion': '2026-09-20T15:00:00+00:00'},
        ],
      });

      expect(insignia.id, 'i-1');
      expect(insignia.nombre, 'Primera huella');
      expect(insignia.descripcion, 'Tu primer kilómetro con TRAZA');
      expect(insignia.icono, 'huella');
      expect(insignia.xpRequerida, 5);
      // Da igual si se guarda en UTC o en hora local: es el mismo instante.
      expect(insignia.obtenidaEl?.toUtc(), DateTime.utc(2026, 9, 20, 15));
      expect(insignia.obtenida, isTrue);
    });

    test('sin obtención embebida, la insignia sigue pendiente', () {
      // RLS solo deja ver las obtenciones propias: una lista vacía es que el
      // usuario todavía no la tiene.
      final insignia = Insignia.desdeSupabase(const {
        'id': 'i-3',
        'nombre': 'Diez mil',
        'descripcion': 'Tus primeros 10 km en una salida',
        'icono': 'diez',
        'xp_requerida': 105,
        'insignias_usuario': [],
      });

      expect(insignia.xpRequerida, 105);
      expect(insignia.obtenidaEl, isNull);
      expect(insignia.obtenida, isFalse);
    });

    test(
      'si la obtención embebida llega como null, también está pendiente',
      () {
        final insignia = Insignia.desdeSupabase(const {
          'id': 'i-3',
          'nombre': 'Diez mil',
          'descripcion': 'Tus primeros 10 km en una salida',
          'icono': 'diez',
          'xp_requerida': 105,
          'insignias_usuario': null,
        });

        expect(insignia.obtenidaEl, isNull);
        expect(insignia.obtenida, isFalse);
      },
    );
    // Las columnas son `not null`: una fila que no encaja es que el esquema y
    // el modelo se desalinearon, y eso se arregla, no se disimula mostrándola
    // como pendiente.
    group('una fila que no encaja con el esquema', () {
      const base = {
        'id': 'i-1',
        'nombre': 'Primera huella',
        'descripcion': 'Tu primer kilómetro con TRAZA',
        'icono': 'huella',
        'xp_requerida': 5,
      };

      test('sin una columna obligatoria lanza FormatException', () {
        final fila = Map<String, dynamic>.of(base)..remove('icono');

        expect(
          () => Insignia.desdeSupabase(fila),
          throwsA(isA<FormatException>()),
        );
      });

      test('una obtención sin fecha lanza FormatException', () {
        expect(
          () => Insignia.desdeSupabase({
            ...base,
            'insignias_usuario': [
              {'fecha_obtencion': null},
            ],
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('una obtención que no es una fila lanza FormatException', () {
        expect(
          () => Insignia.desdeSupabase({
            ...base,
            'insignias_usuario': ['2026-09-20'],
          }),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });

  group('obtenida', () {
    test('depende solo de que haya fecha de obtención', () {
      const pendiente = Insignia(
        id: 'i-1',
        nombre: 'Primera huella',
        descripcion: 'Tu primer kilómetro con TRAZA',
        icono: 'huella',
        xpRequerida: 5,
      );
      final obtenida = Insignia(
        id: 'i-1',
        nombre: 'Primera huella',
        descripcion: 'Tu primer kilómetro con TRAZA',
        icono: 'huella',
        xpRequerida: 5,
        obtenidaEl: DateTime.utc(2026, 9, 20, 15),
      );

      expect(pendiente.obtenida, isFalse);
      expect(obtenida.obtenida, isTrue);
    });
  });

  group('igualdad', () {
    test('dos insignias con los mismos datos son iguales', () {
      final una = Insignia(
        id: 'i-1',
        nombre: 'Primera huella',
        descripcion: 'Tu primer kilómetro con TRAZA',
        icono: 'huella',
        xpRequerida: 5,
        obtenidaEl: DateTime.utc(2026, 9, 20, 15),
      );
      final otra = Insignia(
        id: 'i-1',
        nombre: 'Primera huella',
        descripcion: 'Tu primer kilómetro con TRAZA',
        icono: 'huella',
        xpRequerida: 5,
        obtenidaEl: DateTime.utc(2026, 9, 20, 15),
      );

      expect(una, otra);
      expect(una.hashCode, otra.hashCode);
    });

    test('la misma insignia antes y después de obtenerla no es igual', () {
      // Si fueran iguales, un provider que compara el estado anterior con el
      // nuevo podría no avisar a la pantalla de la insignia recién ganada.
      const antes = Insignia(
        id: 'i-1',
        nombre: 'Primera huella',
        descripcion: 'Tu primer kilómetro con TRAZA',
        icono: 'huella',
        xpRequerida: 5,
      );
      final despues = Insignia(
        id: 'i-1',
        nombre: 'Primera huella',
        descripcion: 'Tu primer kilómetro con TRAZA',
        icono: 'huella',
        xpRequerida: 5,
        obtenidaEl: DateTime.utc(2026, 9, 20, 15),
      );

      expect(antes, isNot(despues));
    });
  });
}
