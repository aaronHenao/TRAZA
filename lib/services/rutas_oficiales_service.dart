import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ruta_oficial.dart';
import '../models/verificacion_ruta.dart';
import 'objetivos_service.dart' show SesionRequeridaException;
import 'retos_service.dart' show SoloAdministradorException;
import 'rutas_service.dart';

/// Repositorio de rutas oficiales que usa la app. Las pruebas lo sustituyen
/// con `overrideWithValue`.
final rutasOficialesRepositoryProvider = Provider<RutasOficialesRepository>(
  (ref) => SupabaseRutasOficialesRepository(),
);

/// La ruta que se quiso agregar no está publicada, o ya no existe.
class RutaNoPublicadaException implements Exception {
  const RutaNoPublicadaException();

  @override
  String toString() => 'RutaNoPublicadaException: la ruta no está publicada';
}

/// La ruta que se quiso agregar ya está en el mapa.
class RutaYaOficialException implements Exception {
  const RutaYaOficialException();

  @override
  String toString() => 'RutaYaOficialException: la ruta ya es oficial';
}

/// La ruta ya no está en el mapa: otra pestaña del administrador la quitó
/// antes de moverla o quitarla, o dejó de ser oficial antes de verificar un
/// recorrido (etapa 4).
class RutaNoOficialException implements Exception {
  const RutaNoOficialException();

  @override
  String toString() => 'RutaNoOficialException: la ruta no es oficial';
}

/// La base no pudo validar el recorrido: no ha terminado, se corrió antes de
/// que la ruta fuera oficial o fue más rápido de lo posible (etapa 4).
class RecorridoNoValidoException implements Exception {
  const RecorridoNoValidoException();

  @override
  String toString() =>
      'RecorridoNoValidoException: la base no pudo validar el recorrido';
}

/// Las rutas del mapa de progresión y su orden (rutas oficiales, etapa 1),
/// cuáles completó el corredor (etapa 2) y la verificación de un recorrido
/// (etapa 4).
abstract interface class RutasOficialesRepository {
  /// Las rutas oficiales en el orden del camino.
  Future<List<RutaOficial>> oficiales();

  /// Pone la ruta al final del camino.
  ///
  /// Lanza [SoloAdministradorException], [RutaNoPublicadaException] o
  /// [RutaYaOficialException].
  Future<void> agregar(String rutaId);

  /// Lleva la ruta a [posicion]; las del medio se corren una.
  ///
  /// Lanza [SoloAdministradorException] o [RutaNoOficialException].
  Future<void> mover(String rutaId, int posicion);

  /// Saca la ruta del mapa; las de atrás suben una.
  ///
  /// Lanza [SoloAdministradorException] o [RutaNoOficialException].
  Future<void> quitar(String rutaId);

  /// Los ids de las rutas que completó el corredor con sesión (etapa 2).
  /// Puede traer rutas que ya no son oficiales: el mapa las ignora.
  Future<Set<String>> completadas();

  /// Pide a la base que compare el recorrido del entrenamiento con su ruta
  /// (etapa 4). Si se completó, la base misma la registra. Null si el
  /// entrenamiento fue libre.
  ///
  /// Lanza [RutaNoOficialException] o [RecorridoNoValidoException].
  Future<VerificacionRuta?> verificar(String entrenamientoId);
}

/// Agregar, mover y quitar van por funciones de la base (`0058`): cada una
/// reacomoda las demás posiciones en la misma transacción, y la tabla no
/// deja escribir directo a nadie.
class SupabaseRutasOficialesRepository implements RutasOficialesRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseRutasOficialesRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'rutas_oficiales';
  static const _tablaCompletadas = 'rutas_completadas';

  /// Códigos que lanzan las funciones de `0058_rutas_oficiales.sql`.
  static const _noEsAdmin = '42501';
  static const _noPublicada = '22023';
  static const _noExiste = 'TZ404';
  static const _yaOficial = 'TZ409';
  static const _noValido = 'TZ422';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<List<RutaOficial>> oficiales() async {
    // La ruta se embebe con las mismas columnas que lee Explorar: sin el
    // trazado, que son cientos de coordenadas que aquí no se dibujan.
    final filas = await _cliente
        .from(_tabla)
        .select('posicion,ruta:rutas(${SupabaseRutasRepository.columnas})')
        .order('posicion', ascending: true);

    return filas.map(RutaOficial.desdeSupabase).toList();
  }

  @override
  Future<void> agregar(String rutaId) async {
    try {
      await _cliente.rpc('agregar_ruta_oficial', params: {'p_ruta_id': rutaId});
    } on PostgrestException catch (e) {
      if (e.code == _noEsAdmin) throw const SoloAdministradorException();
      // Una ruta que ya no existe tampoco está publicada: para quien la
      // eligió de la lista es lo mismo.
      if (e.code == _noPublicada || e.code == _noExiste) {
        throw const RutaNoPublicadaException();
      }
      if (e.code == _yaOficial) throw const RutaYaOficialException();
      rethrow;
    }
  }

  @override
  Future<void> mover(String rutaId, int posicion) => _cambiar(
    'mover_ruta_oficial',
    {'p_ruta_id': rutaId, 'p_posicion': posicion},
  );

  @override
  Future<void> quitar(String rutaId) =>
      _cambiar('quitar_ruta_oficial', {'p_ruta_id': rutaId});

  @override
  Future<Set<String>> completadas() async {
    // La policy de 0059 ya deja ver solo las propias; el filtro va igual,
    // como en el historial: si un día el administrador puede verlas todas,
    // su mapa no mezcla las ajenas.
    final filas = await _cliente
        .from(_tablaCompletadas)
        .select('ruta_id')
        .eq('usuario_id', _usuarioId());
    return {for (final fila in filas) fila['ruta_id'] as String};
  }

  @override
  Future<VerificacionRuta?> verificar(String entrenamientoId) async {
    try {
      final filas = await _cliente.rpc(
        'verificar_ruta_completada',
        params: {'p_entrenamiento_id': entrenamientoId},
      );
      // Sin filas: el entrenamiento fue libre.
      if (filas is! List || filas.isEmpty) return null;
      return VerificacionRuta.desdeSupabase(
        Map<String, dynamic>.from(filas.first as Map),
      );
    } on PostgrestException catch (e) {
      if (e.code == _noExiste) throw const RutaNoOficialException();
      if (e.code == _noValido) throw const RecorridoNoValidoException();
      rethrow;
    }
  }

  String _usuarioId() {
    final usuarioActual = _usuarioActual;
    final id = usuarioActual != null
        ? usuarioActual()
        : _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
    return id;
  }

  Future<void> _cambiar(String funcion, Map<String, dynamic> parametros) async {
    try {
      await _cliente.rpc(funcion, params: parametros);
    } on PostgrestException catch (e) {
      if (e.code == _noEsAdmin) throw const SoloAdministradorException();
      if (e.code == _noExiste) throw const RutaNoOficialException();
      rethrow;
    }
  }
}
