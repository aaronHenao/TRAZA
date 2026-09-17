import 'package:flutter/foundation.dart';

/// Datos de salud medidos durante un entrenamiento (SCRUM-79).
///
/// Cada dato es null si el teléfono o el reloj no lo registró: no todos miden
/// frecuencia cardiaca, por ejemplo.
@immutable
class MetricasSalud {
  const MetricasSalud({
    this.frecuenciaPromedio,
    this.frecuenciaMaxima,
    this.calorias,
    this.pasos,
  });

  /// Arma las métricas a partir de las lecturas crudas de Health Connect o
  /// Apple Health.
  factory MetricasSalud.desdeLecturas({
    required List<num> frecuencias,
    required List<num> calorias,
    required int? pasos,
  }) {
    return MetricasSalud(
      frecuenciaPromedio: frecuencias.isEmpty
          ? null
          : (frecuencias.reduce((a, b) => a + b) / frecuencias.length).round(),
      frecuenciaMaxima: frecuencias.isEmpty
          ? null
          : frecuencias.reduce((a, b) => a > b ? a : b).round(),
      // Las calorías llegan en tramos: se suman.
      calorias: calorias.isEmpty
          ? null
          : calorias.reduce((a, b) => a + b).round(),
      pasos: pasos == null || pasos == 0 ? null : pasos,
    );
  }

  /// Latidos por minuto.
  final int? frecuenciaPromedio;
  final int? frecuenciaMaxima;

  /// Kilocalorías activas (sin contar las que se gastan en reposo).
  final int? calorias;
  final int? pasos;

  /// No se registró nada: el resumen no muestra la sección.
  bool get vacia =>
      frecuenciaPromedio == null &&
      frecuenciaMaxima == null &&
      calorias == null &&
      pasos == null;
}
