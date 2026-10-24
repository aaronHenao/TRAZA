import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ruta.dart';
import '../models/zona.dart';
import 'rutas_service.dart';
import 'ubicacion_provider.dart';
import 'zonas_service.dart';

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

/// Lo que el usuario confirmó con la tecla de buscar, ya como término, o
/// null (SCRUM-255).
///
/// La barra lo borra en cuanto se vuelve a escribir: lo confirmado era lo
/// que había escrito entonces.
final busquedaConfirmadaProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

/// Si la búsqueda que se ve es la que el usuario confirmó.
final busquedaEstaConfirmadaProvider = Provider.autoDispose<bool>((ref) {
  final termino = ref.watch(
    textoBusquedaRutasProvider.select(terminoDeBusqueda),
  );
  return termino != null && ref.watch(busquedaConfirmadaProvider) == termino;
});

/// El lugar que nombra la búsqueda confirmada (SCRUM-255): "Envigado", "El
/// Poblado". Null si no hay búsqueda confirmada o si lo escrito no es ningún
/// lugar, como el nombre de una ruta o de una persona.
///
/// Solo se pregunta al confirmar, nunca mientras se escribe: el servicio de
/// zonas no admite una consulta por cada letra.
final zonaBuscadaProvider = FutureProvider.autoDispose<Zona?>((ref) async {
  if (!ref.watch(busquedaEstaConfirmadaProvider)) return null;

  final termino = ref.watch(busquedaConfirmadaProvider)!;
  final punto = ref.watch(_puntoUsuario);

  return ref
      .watch(buscadorDeZonasProvider)
      .buscar(termino, latitud: punto?.latitud, longitud: punto?.longitud);
});

/// Las rutas que coinciden con lo escrito (SCRUM-254), o null si no hay
/// búsqueda: con menos de [minimoBusquedaRutas] letras, Explorar rutas
/// muestra las cercanas.
///
/// Mientras se escribe, busca por nombre y creador, y espera
/// [esperaBusquedaRutas] antes de consultar. Si mientras tanto el usuario
/// escribe otra letra, esta búsqueda se abandona sin consultar y sale la
/// nueva; la pantalla conserva los resultados anteriores hasta que llegan
/// los nuevos.
///
/// Al confirmar, busca enseguida y suma las rutas que arrancan en el lugar
/// que nombra lo escrito (SCRUM-255). Si no se pudo preguntar por el lugar,
/// busca igual por nombre y creador: la pantalla avisa con lo que dice
/// [zonaBuscadaProvider].
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

  final confirmada = ref.watch(busquedaEstaConfirmadaProvider);
  final punto = ref.watch(_puntoUsuario);
  final repositorio = ref.watch(rutasRepositoryProvider);
  final enCamino = confirmada ? ref.watch(zonaBuscadaProvider.future) : null;

  var abandonada = false;
  ref.onDispose(() => abandonada = true);
  // Confirmar es pedirla ya: sin espera.
  if (!confirmada) await Future<void>.delayed(esperaBusquedaRutas);
  // Lo que devuelva una búsqueda abandonada no se usa: la pantalla ya está
  // esperando la siguiente.
  if (abandonada) return null;

  Zona? zona;
  if (enCamino != null) {
    try {
      zona = await enCamino;
    } catch (_) {
      // Sin el lugar, por nombre y creador.
    }
    if (abandonada) return null;
  }

  return repositorio.buscar(
    termino: termino,
    latitud: punto?.latitud,
    longitud: punto?.longitud,
    zona: zona,
  );
});

/// Dónde está el usuario, si se sabe.
///
/// Solo el punto: que la ubicación pase de "cargando" a "sin permiso" no
/// cambia nada para buscar, y sin el `select` repetiría la búsqueda.
final _puntoUsuario = ubicacionActualProvider.select(
  (ubicacion) => switch (ubicacion.valueOrNull) {
    UbicacionConocida(:final punto) => punto,
    _ => null,
  },
);
