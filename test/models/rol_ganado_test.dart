import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/rol_ganado.dart';

/// Pruebas del modelo de roles que se ganan (SCRUM-225).
void main() {
  group('RolGanable', () {
    test('traduce el valor que guarda la base', () {
      expect(RolGanable.desdeValorDb('experto'), RolGanable.experto);
    });

    test('un rol que esta versión no conoce no revienta, se ignora', () {
      // Los roles los añade una migración: una app vieja puede encontrarse
      // con uno nuevo y tiene que poder seguir leyendo los demás.
      expect(RolGanable.desdeValorDb('maratonista'), isNull);
    });

    test('cada rol tiene cómo se guarda y cómo se nombra', () {
      expect(RolGanable.experto.valorDb, 'experto');
      expect(RolGanable.experto.nombre, 'Runner Experto');
    });
  });

  group('RolGanado.desdeSupabase', () {
    test('lee una fila con su fecha de otorgamiento', () {
      final rol = RolGanado.desdeSupabase(const {
        'id': 'r-1',
        'usuario_id': 'u-1',
        'rol': 'experto',
        'otorgado_en': '2026-10-02T15:00:00+00:00',
        'anunciado_en': null,
      })!;

      expect(rol.rol, RolGanable.experto);
      expect(rol.otorgadoEn, DateTime.parse('2026-10-02T15:00:00Z').toLocal());
      expect(rol.anunciadoEn, isNull);
    });

    test('sin fecha de anuncio, el rol está sin anunciar', () {
      final rol = RolGanado.desdeSupabase(const {
        'rol': 'experto',
        'otorgado_en': '2026-10-02T15:00:00+00:00',
        'anunciado_en': null,
      })!;

      expect(rol.anunciado, isFalse);
    });

    test('con fecha de anuncio, ya se le contó', () {
      final rol = RolGanado.desdeSupabase(const {
        'rol': 'experto',
        'otorgado_en': '2026-10-02T15:00:00+00:00',
        'anunciado_en': '2026-10-02T15:04:00+00:00',
      })!;

      expect(rol.anunciado, isTrue);
      expect(rol.anunciadoEn!.isAfter(rol.otorgadoEn), isTrue);
    });

    test('un rol desconocido devuelve null en vez de fallar', () {
      final rol = RolGanado.desdeSupabase(const {
        'rol': 'maratonista',
        'otorgado_en': '2026-10-02T15:00:00+00:00',
        'anunciado_en': null,
      });

      expect(rol, isNull);
    });

    test('una fila incompleta o con tipos raros no se disimula', () {
      // `rol` y `otorgado_en` son not null en la tabla: una fila así
      // significa que el esquema y el modelo se desalinearon.
      expect(
        () => RolGanado.desdeSupabase(const {'rol': 'experto'}),
        throwsFormatException,
      );
      expect(
        () => RolGanado.desdeSupabase(const {
          'rol': 'experto',
          'otorgado_en': 1759412400,
        }),
        throwsFormatException,
      );
      expect(
        () => RolGanado.desdeSupabase(const {
          'rol': 'experto',
          'otorgado_en': '2026-10-02T15:00:00+00:00',
          'anunciado_en': 42,
        }),
        throwsFormatException,
      );
    });
  });

  test('dos roles con los mismos datos son el mismo', () {
    final uno = RolGanado(
      rol: RolGanable.experto,
      otorgadoEn: DateTime.utc(2026, 10, 2, 15),
    );
    final otro = RolGanado(
      rol: RolGanable.experto,
      otorgadoEn: DateTime.utc(2026, 10, 2, 15),
    );

    expect(uno, otro);
    expect(uno.hashCode, otro.hashCode);
    expect(
      uno,
      isNot(
        RolGanado(
          rol: RolGanable.experto,
          otorgadoEn: DateTime.utc(2026, 10, 2, 15),
          anunciadoEn: DateTime.utc(2026, 10, 2, 16),
        ),
      ),
    );
  });
}
