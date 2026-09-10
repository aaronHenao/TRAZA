import 'package:flutter_test/flutter_test.dart';
import 'package:traza/features/perfil/domain/tipo_objetivo.dart';
import 'package:traza/features/perfil/domain/validacion_objetivo.dart';

void main() {
  group('objetivo de distancia', () {
    const tipo = TipoObjetivo.distancia;

    test('exige un valor', () {
      expect(validarValorObjetivo(tipo, ''), 'Ingresa la distancia');
      expect(validarValorObjetivo(tipo, '   '), 'Ingresa la distancia');
    });

    test('exige un número', () {
      expect(validarValorObjetivo(tipo, 'abc'), 'Ingresa un número válido');
      expect(validarValorObjetivo(tipo, '.'), 'Ingresa un número válido');
    });

    test('acepta decimales con punto o con coma', () {
      expect(validarValorObjetivo(tipo, '7.5'), isNull);
      expect(validarValorObjetivo(tipo, '7,5'), isNull);
      expect(interpretarValorObjetivo(tipo, '7,5'), 7.5);
    });

    test('rechaza valores por debajo del mínimo', () {
      const mensaje = 'El mínimo es 0.1 km por semana';
      expect(validarValorObjetivo(tipo, '0'), mensaje);
      expect(validarValorObjetivo(tipo, '0.05'), mensaje);
    });

    test('admite metas pequeñas desde 0.1 km', () {
      expect(validarValorObjetivo(tipo, '0.1'), isNull);
      expect(validarValorObjetivo(tipo, '0,5'), isNull);
    });

    test('no tiene tope superior: la meta la decide el usuario', () {
      expect(tipo.maximo, isNull);
      expect(validarValorObjetivo(tipo, '1'), isNull);
      expect(validarValorObjetivo(tipo, '99999'), isNull);
    });
  });

  group('objetivo de frecuencia', () {
    const tipo = TipoObjetivo.frecuencia;

    test('acepta de 1 a 7 veces por semana', () {
      expect(validarValorObjetivo(tipo, '1'), isNull);
      expect(validarValorObjetivo(tipo, '7'), isNull);
      expect(
        validarValorObjetivo(tipo, '0'),
        'El mínimo es 1 veces por semana',
      );
      expect(
        validarValorObjetivo(tipo, '8'),
        'El máximo es 7 veces por semana',
      );
    });

    test('no admite decimales', () {
      expect(validarValorObjetivo(tipo, '3.5'), 'Usa solo números enteros');
    });
  });

  test('formatea sin decimales sobrantes', () {
    expect(formatearValorObjetivo(10), '10');
    expect(formatearValorObjetivo(10.0), '10');
    expect(formatearValorObjetivo(7.5), '7.5');
  });

  test('el tipo se serializa igual que la columna objetivos.tipo', () {
    expect(TipoObjetivo.distancia.valorDb, 'distancia');
    expect(TipoObjetivo.frecuencia.valorDb, 'frecuencia');
  });
}
