import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dificultad.dart';
import '../models/filtros_rutas.dart';
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

/// La dificultad elegida en Explorar rutas, o null para verlas todas
/// (HU-36).
///
/// La eligen los chips de la fila de dificultades (SCRUM-267), y se combina
/// con la distancia (SCRUM-275). Mientras las rutas no tengan dificultad
/// (SCRUM-363), ninguna pasa este filtro.
final dificultadRutasProvider = StateProvider.autoDispose<Dificultad?>(
  (ref) => null,
);

/// Todo lo elegido para filtrar, junto: lo que aplica la lista (SCRUM-275).
final filtrosRutasProvider = Provider.autoDispose<FiltrosRutas>(
  (ref) => FiltrosRutas(
    dificultad: ref.watch(dificultadRutasProvider),
    distancia: ref.watch(rangoDistanciaProvider),
  ),
);
