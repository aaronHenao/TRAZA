import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ruta.dart';
import '../models/ruta_oficial.dart';
import '../models/verificacion_ruta.dart';
import 'retos_service.dart' show SoloAdministradorException;
import 'rutas_oficiales_service.dart';
import 'rutas_service.dart';

/// Las rutas del mapa en el orden del camino (rutas oficiales, etapa 1).
///
/// `autoDispose`: se vuelve a consultar cada vez que se entra.
final rutasOficialesProvider = FutureProvider.autoDispose<List<RutaOficial>>(
  (ref) => ref.watch(rutasOficialesRepositoryProvider).oficiales(),
);

/// Lo que el administrador puede agregar: publicadas que todavía no están
/// en el mapa.
final candidatasRutaOficialProvider = FutureProvider.autoDispose<List<Ruta>>((
  ref,
) async {
  final oficiales = await ref.watch(rutasOficialesProvider.future);
  final enElMapa = {for (final oficial in oficiales) oficial.ruta.id};
  final publicadas = await ref.watch(rutasRepositoryProvider).publicadas();
  return [
    for (final ruta in publicadas)
      if (ruta.publicada && !enElMapa.contains(ruta.id)) ruta,
  ];
});

/// Si el entrenamiento completó su ruta oficial, según la base (etapa 4).
/// Null si fue libre.
///
/// `autoDispose`: se vuelve a preguntar cada vez que se abre el resumen. No
/// duplica nada: la base registra una ruta completada una sola vez.
final verificacionRutaProvider = FutureProvider.autoDispose
    .family<VerificacionRuta?, String>(
      (ref, entrenamientoId) => ref
          .watch(rutasOficialesRepositoryProvider)
          .verificar(entrenamientoId),
    );

/// Agregar, mover y quitar rutas oficiales (etapa 1).
final gestionRutasOficialesProvider = Provider<GestionRutasOficiales>(
  GestionRutasOficiales.new,
);

/// El administrador arma el camino de rutas oficiales (etapa 1).
///
/// Cada acción devuelve null si salió bien, o el mensaje para mostrar. Al
/// terminar, bien o mal, vuelve a consultar la lista y las candidatas: si
/// falló porque otra pestaña ya cambió el mapa, se ve cómo quedó.
class GestionRutasOficiales {
  const GestionRutasOficiales(this._ref);

  final Ref _ref;

  static const soloAdministrador =
      'Solo el administrador gestiona las rutas oficiales';
  static const noPublicada = 'Esa ruta ya no está publicada';
  static const yaOficial = 'Esa ruta ya es oficial';
  static const noOficial = 'Esa ruta ya no está en el mapa';
  static const noSePudo = 'No se pudo guardar el cambio';

  Future<String?> agregar(Ruta ruta) =>
      _hacer((repositorio) => repositorio.agregar(ruta.id));

  Future<String?> subir(RutaOficial oficial) => _hacer(
    (repositorio) => repositorio.mover(oficial.ruta.id, oficial.posicion - 1),
  );

  Future<String?> bajar(RutaOficial oficial) => _hacer(
    (repositorio) => repositorio.mover(oficial.ruta.id, oficial.posicion + 1),
  );

  Future<String?> quitar(RutaOficial oficial) =>
      _hacer((repositorio) => repositorio.quitar(oficial.ruta.id));

  Future<String?> _hacer(
    Future<void> Function(RutasOficialesRepository repositorio) accion,
  ) async {
    try {
      await accion(_ref.read(rutasOficialesRepositoryProvider));
      return null;
    } on SoloAdministradorException {
      return soloAdministrador;
    } on RutaNoPublicadaException {
      return noPublicada;
    } on RutaYaOficialException {
      return yaOficial;
    } on RutaNoOficialException {
      return noOficial;
    } catch (error) {
      // Al usuario, nunca el error crudo de la base; en consola sí, para
      // depurar. No lleva datos personales: solo ids de rutas.
      debugPrint('No se pudo cambiar el mapa de rutas oficiales: $error');
      return noSePudo;
    } finally {
      _ref
        ..invalidate(rutasOficialesProvider)
        ..invalidate(candidatasRutaOficialProvider);
    }
  }
}
