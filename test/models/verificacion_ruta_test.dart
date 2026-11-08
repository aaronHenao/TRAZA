import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/verificacion_ruta.dart';

/// Pruebas del resultado de comparar un recorrido con su ruta oficial
/// (rutas oficiales, etapa 4).
///
/// Si la ruta se completó lo decide `verificar_ruta_completada` en la base;
/// aquí solo se lee su respuesta y se convierte en los porcentajes que ve
/// el corredor.
void main() {
  // Una fila de `verificar_ruta_completada`.
  Map<String, dynamic> fila({
    Object? cobertura = 0.72,
    Object? necesaria = 0.9,
    Object? completada = false,
  }) => {
    'cobertura': cobertura,
    'necesaria': necesaria,
    'completada': completada,
  };

  VerificacionRuta conCobertura(double cobertura) =>
      VerificacionRuta(cobertura: cobertura, necesaria: 0.9, completada: false);

  group('desdeSupabase', () {
    test('lee la cobertura, el umbral y si se completó', () {
      final verificacion = VerificacionRuta.desdeSupabase(fila());

      expect(verificacion.cobertura, 0.72);
      expect(verificacion.necesaria, 0.9);
      expect(verificacion.completada, isFalse);
    });

    test('una ruta completada se lee como completada', () {
      final verificacion = VerificacionRuta.desdeSupabase(
        fila(cobertura: 0.95, completada: true),
      );

      expect(verificacion.cobertura, 0.95);
      expect(verificacion.completada, isTrue);
    });

    test('los numeric que llegan como texto se leen como número', () {
      // PostgREST puede mandar un `numeric` como texto para no perder
      // precisión.
      final verificacion = VerificacionRuta.desdeSupabase(
        fila(cobertura: '0.72', necesaria: '0.90'),
      );

      expect(verificacion.cobertura, 0.72);
      expect(verificacion.necesaria, 0.9);
    });

    test('una cobertura entera (toda la ruta) se lee como 1.0', () {
      final verificacion = VerificacionRuta.desdeSupabase(
        fila(cobertura: 1, necesaria: 1, completada: true),
      );

      expect(verificacion.cobertura, 1.0);
      expect(verificacion.necesaria, 1.0);
      expect(verificacion.porcentaje, 100);
    });

    for (final clave in ['cobertura', 'necesaria', 'completada']) {
      test('una fila sin "$clave" no se acepta', () {
        // La función y la clase se desalinearon: se arregla, no se disimula
        // con un cero.
        expect(
          () => VerificacionRuta.desdeSupabase(fila()..remove(clave)),
          throwsFormatException,
        );
      });

      test('una fila con "$clave" en null no se acepta', () {
        expect(
          () => VerificacionRuta.desdeSupabase(fila()..[clave] = null),
          throwsFormatException,
        );
      });
    }

    test('una cobertura que no es un número no se acepta', () {
      expect(
        () => VerificacionRuta.desdeSupabase(fila(cobertura: 'mucho')),
        throwsFormatException,
      );
    });

    test('un umbral que no es un número no se acepta', () {
      expect(
        () => VerificacionRuta.desdeSupabase(fila(necesaria: 'noventa')),
        throwsFormatException,
      );
    });
  });

  group('porcentaje cubierto (criterio 3): redondeado hacia abajo', () {
    test('0.899 es 89 %: nunca muestra 90 si no llegó', () {
      expect(conCobertura(0.899).porcentaje, 89);
    });

    test('justo en el umbral, 0.9, es 90 %', () {
      expect(conCobertura(0.9).porcentaje, 90);
    });

    test('0.72 es 72 %', () {
      expect(conCobertura(0.72).porcentaje, 72);
    });

    test('sin cobertura es 0 % y con toda la ruta, 100 %', () {
      expect(conCobertura(0).porcentaje, 0);
      expect(conCobertura(1).porcentaje, 100);
    });

    test('una cobertura exacta no pierde un punto por el redondeo de los '
        'decimales', () {
      // En doble precisión 0.29 * 100 da 28.999999999999996: redondear eso
      // hacia abajo diría 28 % a quien cubrió 29 de 100 puntos.
      expect(conCobertura(0.29).porcentaje, 29);
      expect(conCobertura(0.57).porcentaje, 57);
      expect(conCobertura(0.58).porcentaje, 58);
    });
  });

  group('porcentaje necesario (criterio 3): el umbral de la base, '
      'redondeado', () {
    VerificacionRuta conUmbral(double necesaria) => VerificacionRuta(
      cobertura: 0.5,
      necesaria: necesaria,
      completada: false,
    );

    test('0.9 es 90 %', () {
      expect(conUmbral(0.9).porcentajeNecesario, 90);
    });

    test('si la base cambia el umbral, el porcentaje lo sigue', () {
      expect(conUmbral(0.85).porcentajeNecesario, 85);
      expect(conUmbral(0.875).porcentajeNecesario, 88);
    });
  });

  group('igualdad', () {
    test('dos con los mismos datos son iguales', () {
      final una = VerificacionRuta.desdeSupabase(fila());
      final otra = VerificacionRuta.desdeSupabase(fila());

      expect(una, otra);
      expect(una.hashCode, otra.hashCode);
    });

    test('otra cobertura, otro umbral u otro resultado no son iguales', () {
      const base = VerificacionRuta(
        cobertura: 0.72,
        necesaria: 0.9,
        completada: false,
      );

      expect(
        base,
        isNot(
          const VerificacionRuta(
            cobertura: 0.73,
            necesaria: 0.9,
            completada: false,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const VerificacionRuta(
            cobertura: 0.72,
            necesaria: 0.8,
            completada: false,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const VerificacionRuta(
            cobertura: 0.72,
            necesaria: 0.9,
            completada: true,
          ),
        ),
      );
    });
  });
}
