import 'resumen_entrenamiento.dart';

/// Formato y validación de los entrenamientos del historial (SCRUM-126).
///
/// Cada entrenamiento es un [ResumenEntrenamiento] sin puntos GPS: así la
/// lista y el resumen formatean fechas, tiempo y distancia exactamente igual.
extension HistorialDeEntrenamiento on ResumenEntrenamiento {
  /// Segunda línea de la fila, como el prototipo: `5.10 km · 00:28:14`.
  ///
  /// Si la distancia no se calculó, solo el tiempo: `— · 00:28:14` no le dice
  /// nada al usuario.
  String get detalleHistorial =>
      distanciaMetros == null ? tiempo : '$distancia · $tiempo';
}

/// Deja listas las filas que llegaron de Supabase:
///
/// - Descarta las incompletas (llegan como null) y las que tienen una duración
///   negativa, que solo pueden venir de un dato corrupto.
/// - Quita repetidas por id.
/// - Ordena de la más reciente a la más antigua, aunque la consulta ya lo
///   pida, para no depender de ella.
List<ResumenEntrenamiento> prepararHistorial(
  Iterable<ResumenEntrenamiento?> filas,
) {
  final vistos = <String?>{};
  final validas = [
    for (final fila in filas)
      if (fila != null &&
          !fila.duracion.isNegative &&
          vistos.add(fila.entrenamientoId))
        fila,
  ];
  validas.sort((a, b) => b.fechaFin.compareTo(a.fechaFin));
  return validas;
}
