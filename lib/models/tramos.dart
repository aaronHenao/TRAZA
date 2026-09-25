/// Tramos de un recorrido: lo que se recorre entre dos pausas (BUG-005).
///
/// Los puntos se guardan en una sola lista, en orden de captura; los
/// `cortes` son los índices donde empieza un tramo nuevo (el primer punto
/// tras reanudar). El primer tramo empieza en 0 y no aparece en los cortes.
library;

/// [elementos] separados en tramos según [cortes] (índices crecientes).
List<List<T>> dividirEnTramos<T>(List<T> elementos, List<int> cortes) {
  if (elementos.isEmpty) return const [];
  final limites = [0, ...cortes, elementos.length];
  return [
    for (var i = 0; i < limites.length - 1; i++)
      elementos.sublist(limites[i], limites[i + 1]),
  ];
}

/// Cortes a partir del número de tramo de cada punto, como se guarda en la
/// columna `puntos_gps.tramo`: empieza un tramo donde el número cambia.
List<int> cortesDesdeTramos(List<int> tramoPorPunto) => [
  for (var i = 1; i < tramoPorPunto.length; i++)
    if (tramoPorPunto[i] != tramoPorPunto[i - 1]) i,
];

/// Número de tramo de cada uno de [cantidad] puntos, para guardarlo en
/// `puntos_gps.tramo`: 0 hasta el primer corte, 1 hasta el segundo...
List<int> tramosDesdeCortes(int cantidad, List<int> cortes) {
  var tramo = 0;
  return [
    for (var i = 0; i < cantidad; i++)
      if (tramo < cortes.length && cortes[tramo] == i) ++tramo else tramo,
  ];
}
