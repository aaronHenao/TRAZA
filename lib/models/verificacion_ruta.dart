import 'package:flutter/foundation.dart';

/// Lo que respondió la base al comparar un entrenamiento con su ruta
/// oficial (rutas oficiales, etapa 4; `verificar_ruta_completada`, 0061).
///
/// Solo se muestra: si se completó lo decide la base, no la app.
@immutable
class VerificacionRuta {
  const VerificacionRuta({
    required this.cobertura,
    required this.necesaria,
    required this.completada,
  });

  /// Fila de `verificar_ruta_completada`. Los `numeric` de Postgres pueden
  /// llegar como número o como texto.
  factory VerificacionRuta.desdeSupabase(Map<String, dynamic> fila) {
    final cobertura = _comoDouble(fila['cobertura']);
    final necesaria = _comoDouble(fila['necesaria']);
    final completada = fila['completada'];
    if (cobertura == null || necesaria == null || completada is! bool) {
      throw FormatException('Verificación de ruta inesperada', fila);
    }
    return VerificacionRuta(
      cobertura: cobertura,
      necesaria: necesaria,
      completada: completada,
    );
  }

  /// Qué parte del trazado se recorrió, de 0 a 1.
  final double cobertura;

  /// Qué parte hace falta para completarla, de 0 a 1. La fija la base.
  final double necesaria;

  final bool completada;

  /// La cobertura en porcentaje, hacia abajo: con 0.899 dice 89, nunca 90
  /// sin haber llegado. Se redondea primero a milésimas (lo que guarda la
  /// base) para que 0.29 no se vuelva 28 por los decimales de `double`.
  int get porcentaje => (cobertura * 1000).round() ~/ 10;

  int get porcentajeNecesario => (necesaria * 100).round();

  static double? _comoDouble(Object? valor) => switch (valor) {
    final num numero => numero.toDouble(),
    final String texto => double.tryParse(texto),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is VerificacionRuta &&
      other.cobertura == cobertura &&
      other.necesaria == necesaria &&
      other.completada == completada;

  @override
  int get hashCode => Object.hash(cobertura, necesaria, completada);

  @override
  String toString() =>
      'VerificacionRuta($porcentaje % de $porcentajeNecesario %'
      '${completada ? ', completada' : ''})';
}
