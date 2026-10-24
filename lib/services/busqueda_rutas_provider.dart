import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ruta.dart';
import 'rutas_service.dart';
import 'ubicacion_provider.dart';

/// Cuánto se espera a que el usuario deje de escribir para buscar
/// (SCRUM-254).
///
/// Sin esto saldría una consulta por cada letra. Es más de lo que tarda en
/// llegar la siguiente letra de quien sigue escribiendo, y poco para quien
/// ya terminó.
const esperaBusquedaRutas = Duration(milliseconds: 350);

/// Las letras que hacen falta para buscar: con una sola coincide casi todo,
/// y la base (0040) la rechaza.
const minimoBusquedaRutas = 2;

/// Lo que de verdad se busca a partir de lo escrito: sin espacios en los
/// extremos y con los de en medio reducidos a uno, como lo compara la base.
/// Null si no alcanza para buscar.
String? terminoDeBusqueda(String escrito) {
  final termino = escrito.trim().replaceAll(RegExp(r'\s+'), ' ');
  return termino.length >= minimoBusquedaRutas ? termino : null;
}

/// Lo que el usuario escribió en la barra de Explorar rutas, tal cual.
final textoBusquedaRutasProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

/// Las rutas que coinciden con lo escrito (SCRUM-254), o null si no hay
/// búsqueda: con menos de [minimoBusquedaRutas] letras, Explorar rutas
/// muestra las cercanas.
///
/// Espera [esperaBusquedaRutas] antes de consultar. Si mientras tanto el
/// usuario escribe otra letra, esta búsqueda se abandona sin consultar y
/// sale la nueva; la pantalla conserva los resultados anteriores hasta que
/// llegan los nuevos.
///
/// Si ya se sabe dónde está el usuario, van de la más cercana a la más
/// lejana. No espera a saberlo: buscar no depende de eso, y si la ubicación
/// llega después, la búsqueda se repite ya ordenada.
final busquedaRutasProvider = FutureProvider.autoDispose<List<Ruta>?>((
  ref,
) async {
  // Con `select`, un espacio de más al final no dispara otra búsqueda.
  final termino = ref.watch(
    textoBusquedaRutasProvider.select(terminoDeBusqueda),
  );
  if (termino == null) return null;

  final ubicacion = ref.watch(ubicacionActualProvider).valueOrNull;
  final repositorio = ref.watch(rutasRepositoryProvider);

  var abandonada = false;
  ref.onDispose(() => abandonada = true);
  await Future<void>.delayed(esperaBusquedaRutas);
  // Lo que devuelva una búsqueda abandonada no se usa: la pantalla ya está
  // esperando la siguiente.
  if (abandonada) return null;

  final punto = switch (ubicacion) {
    UbicacionConocida(:final punto) => punto,
    _ => null,
  };

  return repositorio.buscar(
    termino: termino,
    latitud: punto?.latitud,
    longitud: punto?.longitud,
  );
});
