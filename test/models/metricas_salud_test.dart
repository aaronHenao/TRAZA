import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/metricas_salud.dart';

/// Cálculo de las métricas de salud del resumen (SCRUM-79).
void main() {
  test('promedia y toma el máximo de la frecuencia cardiaca', () {
    final metricas = MetricasSalud.desdeLecturas(
      frecuencias: [120, 140, 161],
      calorias: const [],
      pasos: null,
    );

    expect(metricas.frecuenciaPromedio, 140);
    expect(metricas.frecuenciaMaxima, 161);
  });

  test('suma los tramos de calorías', () {
    final metricas = MetricasSalud.desdeLecturas(
      frecuencias: const [],
      calorias: [80.4, 120.3, 99.6],
      pasos: 4200,
    );

    expect(metricas.calorias, 300);
    expect(metricas.pasos, 4200);
  });

  test('sin lecturas queda vacía', () {
    final metricas = MetricasSalud.desdeLecturas(
      frecuencias: const [],
      calorias: const [],
      pasos: 0,
    );

    expect(metricas.vacia, isTrue);
    expect(metricas.pasos, isNull);
  });
}
