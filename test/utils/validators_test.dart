import 'package:flutter_test/flutter_test.dart';
import 'package:traza/utils/validators.dart';

void main() {
  group('Criterio 3 — validarCorreo', () {
    test('rechaza el campo vacío', () {
      expect(validarCorreo(''), 'Ingresa tu correo electrónico');
    });

    test('rechaza un correo sin @', () {
      expect(validarCorreo('juangmail.com'), isNotNull);
    });

    test('rechaza un correo sin punto en el dominio', () {
      expect(validarCorreo('juan@gmail'), isNotNull);
    });

    test('acepta un correo válido', () {
      expect(validarCorreo('juan@gmail.com'), isNull);
    });

    // Decisión de SCRUM-47: no se limita a .com y .co.
    test('acepta dominios distintos de .com y .co', () {
      expect(validarCorreo('juan@hotmail.es'), isNull);
    });

    test('ignora espacios al inicio y al final', () {
      expect(validarCorreo('  juan@gmail.com  '), isNull);
    });
  });

  group('Criterio 4 — validarPassword', () {
    test('rechaza el campo vacío', () {
      expect(validarPassword(''), 'Ingresa una contraseña');
    });

    test('rechaza menos de 8 caracteres', () {
      expect(validarPassword('Ab1!'), 'Debe tener al menos 8 caracteres');
    });

    test('rechaza sin mayúscula', () {
      expect(
        validarPassword('abcdefg1!'),
        'Debe incluir al menos una letra mayúscula',
      );
    });

    test('rechaza sin minúscula', () {
      expect(
        validarPassword('ABCDEFG1!'),
        'Debe incluir al menos una letra minúscula',
      );
    });

    test('rechaza sin número', () {
      expect(validarPassword('Abcdefgh!'), 'Debe incluir al menos un número');
    });

    test('rechaza sin carácter especial', () {
      expect(
        validarPassword('Abcdefg1'),
        'Debe incluir al menos un carácter especial',
      );
    });

    test('el espacio no cuenta como carácter especial', () {
      expect(
        validarPassword('Abcdefg 1'),
        'Debe incluir al menos un carácter especial',
      );
    });

    test('acepta una contraseña que cumple todo', () {
      expect(validarPassword('Abcdefg1!'), isNull);
    });

    test('el checklist marca todas las reglas en una contraseña válida', () {
      expect(reglasPassword.every((r) => r.cumple('Abcdefg1!')), isTrue);
    });
  });

  group('validarNombre', () {
    test('rechaza el campo vacío', () {
      expect(validarNombre(''), 'Ingresa tu nombre');
    });

    test('rechaza solo espacios', () {
      expect(validarNombre('   '), 'Ingresa tu nombre');
    });

    test('acepta un nombre válido', () {
      expect(validarNombre('Ana'), isNull);
    });
  });
}
