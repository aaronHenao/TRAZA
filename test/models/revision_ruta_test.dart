import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/revision_ruta.dart';

/// Las reglas del rechazo de una ruta (SCRUM-321). Las etiquetas de cada
/// etapa las prueba `ruta_test.dart`.
void main() {
  group('errorDelMotivo (criterio 6)', () {
    test('sin motivo no se puede rechazar', () {
      expect(errorDelMotivo(null), 'El motivo es obligatorio.');
      expect(errorDelMotivo(''), 'El motivo es obligatorio.');
    });

    test('un motivo de solo espacios tampoco cuenta', () {
      expect(errorDelMotivo('   \n '), 'El motivo es obligatorio.');
    });

    test('acepta el motivo justo en el limite y rechaza uno mas', () {
      expect(errorDelMotivo('a' * maxCaracteresMotivoRechazo), isNull);
      expect(
        errorDelMotivo('a' * (maxCaracteresMotivoRechazo + 1)),
        contains('300'),
      );
    });

    test('los espacios de los extremos no cuentan para el limite', () {
      expect(errorDelMotivo('  ${'a' * maxCaracteresMotivoRechazo}  '), isNull);
    });
  });
}
