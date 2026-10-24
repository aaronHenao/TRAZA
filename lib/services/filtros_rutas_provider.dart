import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rango_distancia.dart';
import '../models/ruta.dart';

/// El rango de distancia elegido en Explorar rutas, o null si no hay
/// ninguno (SCRUM-273).
///
/// Uno a la vez: elegir otro reemplaza al anterior, y tocar el elegido lo
/// quita. Vale para las cercanas y para los resultados de una búsqueda, y
/// se olvida al salir de la sección.
final rangoDistanciaProvider = StateProvider.autoDispose<RangoDistancia?>(
  (ref) => null,
);

/// Las rutas de [rutas] que cumplen los filtros elegidos, en el mismo orden
/// (SCRUM-274, criterio 2 de HU-37).
///
/// Se filtra en la app, sobre la lista que ya llegó —las cercanas, las
/// recientes o lo que encontró una búsqueda—, así que cambiar de rango no
/// vuelve a consultar: el cambio se ve al instante, y quitar el filtro
/// devuelve la lista tal como estaba (criterio 4). Cada lista trae un máximo
/// de rutas (`SupabaseRutasRepository.limite`), y el filtro trabaja sobre
/// esas.
///
/// Hoy el único filtro es la distancia. El de dificultad (HU-36) se suma
/// aquí como una condición más, y una ruta tendrá que cumplir las dos
/// (criterio 3).
List<Ruta> filtrarRutas(List<Ruta> rutas, {RangoDistancia? distancia}) {
  if (distancia == null) return rutas;
  return [
    for (final ruta in rutas)
      if (distancia.contiene(ruta.distanciaKm)) ruta,
  ];
}
