import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rango_distancia.dart';

/// El rango de distancia elegido en Explorar rutas, o null si no hay
/// ninguno (SCRUM-273).
///
/// Uno a la vez: elegir otro reemplaza al anterior, y tocar el elegido lo
/// quita. Vale para las cercanas y para los resultados de una búsqueda, y
/// se olvida al salir de la sección.
final rangoDistanciaProvider = StateProvider.autoDispose<RangoDistancia?>(
  (ref) => null,
);
