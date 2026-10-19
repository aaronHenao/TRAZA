import 'package:flutter_test/flutter_test.dart';
import 'package:traza/utils/fecha_relativa.dart';

void main() {
  final ahora = DateTime(2026, 10, 16, 18);

  group('fechaYHoraRelativa', () {
    test('de mañana y de tarde, con minutos de dos cifras', () {
      expect(
        fechaYHoraRelativa(DateTime(2026, 10, 16, 9, 5), ahora),
        'Hoy, 9:05 a. m.',
      );
      expect(
        fechaYHoraRelativa(DateTime(2026, 10, 15, 15, 30), ahora),
        'Ayer, 3:30 p. m.',
      );
    });

    test('medianoche y mediodía son las 12', () {
      expect(
        fechaYHoraRelativa(DateTime(2026, 10, 16), ahora),
        'Hoy, 12:00 a. m.',
      );
      expect(
        fechaYHoraRelativa(DateTime(2026, 10, 2, 12), ahora),
        '2 oct, 12:00 p. m.',
      );
    });
  });
}
