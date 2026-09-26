import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/nuevo_nivel.dart';

/// Pruebas de las reglas que impiden registrar un nivel mal formado
/// (SCRUM-181), ampliadas con los casos límite de SCRUM-184.
void main() {
  const existentes = [
    Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
    Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500),
  ];

  group('nombre', () {
    test('sin nombre no se puede registrar', () {
      const borrador = BorradorNivel(umbral: '900');

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.nombre],
        'Ponle un nombre al nivel.',
      );
      expect(borrador.aNuevoNivel(existentes), isNull);
    });

    test('un nombre de puros espacios tampoco es un nombre', () {
      const borrador = BorradorNivel(nombre: '   ', umbral: '900');

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.nombre],
        'Ponle un nombre al nivel.',
      );
    });

    test('rechaza un nombre más largo de lo que cabe', () {
      final borrador = BorradorNivel(
        nombre: 'a' * (maxCaracteresNombreNivel + 1),
        umbral: '900',
      );

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.nombre],
        'Máximo $maxCaracteresNombreNivel caracteres.',
      );
    });

    test('dice con qué nivel se repite el nombre', () {
      const borrador = BorradorNivel(nombre: 'Bronce', umbral: '900');

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.nombre],
        'Ya existe un nivel llamado "Bronce".',
      );
    });

    test('el nombre repetido se detecta sin importar mayúsculas ni '
        'espacios', () {
      // La tabla compara igual: su índice único es sobre lower(btrim(nombre)).
      const borrador = BorradorNivel(nombre: '  bronce ', umbral: '900');

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.nombre],
        'Ya existe un nivel llamado "Bronce".',
      );
    });

    test('un nombre de justo el máximo cabe', () {
      // El límite es inclusivo: 40 caracteres se aceptan, 41 no.
      final borrador = BorradorNivel(
        nombre: 'a' * maxCaracteresNombreNivel,
        umbral: '900',
      );

      expect(borrador.erroresFrenteA(existentes), isEmpty);
    });

    test('el límite cuenta el nombre sin los espacios de los extremos', () {
      final borrador = BorradorNivel(
        nombre: '  ${'a' * maxCaracteresNombreNivel}  ',
        umbral: '900',
      );

      expect(borrador.erroresFrenteA(existentes), isEmpty);
    });
  });

  group('umbral', () {
    test('sin umbral no se puede registrar', () {
      const borrador = BorradorNivel(nombre: 'Oro');

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.umbral],
        'Indica la experiencia necesaria para alcanzarlo.',
      );
    });

    test('rechaza lo que no sea un número entero', () {
      for (final escrito in ['mil', '1.5', '1,5', '900 xp']) {
        final borrador = BorradorNivel(nombre: 'Oro', umbral: escrito);

        expect(
          borrador.erroresFrenteA(existentes)[CampoNivel.umbral],
          'Usa solo números enteros.',
          reason: 'con "$escrito"',
        );
      }
    });

    test('rechaza el cero y los negativos', () {
      for (final escrito in ['0', '-1', '-900']) {
        final borrador = BorradorNivel(nombre: 'Oro', umbral: escrito);

        expect(
          borrador.erroresFrenteA(existentes)[CampoNivel.umbral],
          'El umbral debe ser mayor que cero.',
          reason: 'con "$escrito"',
        );
      }
    });

    test('dice con qué nivel se solapa el umbral', () {
      const borrador = BorradorNivel(nombre: 'Oro', umbral: '500');

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.umbral],
        'Ese umbral ya lo usa "Plata". Cada nivel empieza en uno distinto.',
      );
      expect(borrador.aNuevoNivel(existentes), isNull);
    });

    test('un umbral entre dos niveles no se solapa con ninguno', () {
      // Solapar es empezar donde ya empieza otro; meterse en medio de la
      // progresión es lo normal y tiene que dejarse.
      const borrador = BorradorNivel(nombre: 'Hierro', umbral: '250');

      expect(borrador.erroresFrenteA(existentes), isEmpty);
    });

    test('un umbral un punto al lado del de otro nivel es válido', () {
      for (final escrito in ['99', '101']) {
        final borrador = BorradorNivel(nombre: 'Hierro', umbral: escrito);

        expect(
          borrador.erroresFrenteA(existentes),
          isEmpty,
          reason: 'con "$escrito"',
        );
      }
    });

    test('un umbral más grande de lo que cabe en un entero se rechaza', () {
      const borrador = BorradorNivel(
        nombre: 'Oro',
        umbral: '99999999999999999999',
      );

      expect(
        borrador.erroresFrenteA(existentes)[CampoNivel.umbral],
        'Usa solo números enteros.',
      );
    });
  });

  group('cuando está todo bien', () {
    test('sin errores se puede registrar', () {
      const borrador = BorradorNivel(nombre: 'Oro', umbral: '1500');

      expect(borrador.erroresFrenteA(existentes), isEmpty);
      expect(borrador.esValidoFrenteA(existentes), isTrue);
      expect(
        borrador.aNuevoNivel(existentes),
        const NuevoNivel(nombre: 'Oro', umbralExperiencia: 1500),
      );
    });

    test('guarda el nombre sin los espacios de los extremos', () {
      const borrador = BorradorNivel(nombre: '  Oro  ', umbral: ' 1500 ');

      expect(
        borrador.aNuevoNivel(existentes),
        const NuevoNivel(nombre: 'Oro', umbralExperiencia: 1500),
      );
    });

    test('el primer nivel del sistema no choca con nadie', () {
      const borrador = BorradorNivel(nombre: 'Bronce', umbral: '100');

      expect(borrador.erroresFrenteA(const []), isEmpty);
    });

    test('señala los dos choques cuando el nombre y el umbral ya existen', () {
      // Copiar un nivel entero: ninguno de los dos campos sirve como está.
      const borrador = BorradorNivel(nombre: 'Plata', umbral: '500');

      expect(borrador.erroresFrenteA(existentes), {
        CampoNivel.nombre: 'Ya existe un nivel llamado "Plata".',
        CampoNivel.umbral:
            'Ese umbral ya lo usa "Plata". Cada nivel empieza en uno distinto.',
      });
      expect(borrador.esValidoFrenteA(existentes), isFalse);
    });

    test('si solo choca el nombre, el umbral no se marca', () {
      const borrador = BorradorNivel(nombre: 'Plata', umbral: '900');

      expect(borrador.erroresFrenteA(existentes).keys, [CampoNivel.nombre]);
    });

    test('señala los dos campos a la vez cuando los dos están mal', () {
      const borrador = BorradorNivel(nombre: '', umbral: '0');

      expect(borrador.erroresFrenteA(existentes), {
        CampoNivel.nombre: 'Ponle un nombre al nivel.',
        CampoNivel.umbral: 'El umbral debe ser mayor que cero.',
      });
    });

    test('copyWith cambia solo lo que se le pasa', () {
      const borrador = BorradorNivel(nombre: 'Oro', umbral: '1500');

      expect(borrador.copyWith(umbral: '2000').nombre, 'Oro');
      expect(borrador.copyWith(umbral: '2000').umbral, '2000');
    });
  });
}
