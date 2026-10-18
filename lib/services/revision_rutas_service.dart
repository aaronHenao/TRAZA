import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/revision_ruta.dart';
import '../models/ruta.dart';
import 'foro_service.dart' show usuarioActualProvider;

/// Repositorio de la revisión de rutas que usa la app. Las pruebas lo
/// sustituyen con `overrideWithValue`.
///
/// Va aparte de `RutasRepository` (SCRUM-241): ese es lo que hace el autor con
/// sus rutas, y esto lo que hacen el administrador y el Runner Experto con las
/// de los demás.
final revisionRutasRepositoryProvider = Provider<RevisionRutasRepository>(
  (ref) => SupabaseRevisionRutasRepository(
    usuarioActual: ref.read(usuarioActualProvider),
  ),
);

/// Se lanza cuando se intenta revisar sin una sesión abierta.
class SesionRequeridaParaRevisarException implements Exception {
  const SesionRequeridaParaRevisarException();

  @override
  String toString() =>
      'SesionRequeridaParaRevisarException: no hay una sesión abierta';
}

/// Se lanza cuando quien decide no tiene el rol de la etapa en que está la
/// ruta, o es su autor.
class RevisionNoPermitidaException implements Exception {
  const RevisionNoPermitidaException();

  @override
  String toString() =>
      'RevisionNoPermitidaException: no tienes el rol de esta etapa o la ruta '
      'es tuya';
}

/// Se lanza cuando la base no acepta el motivo del rechazo: vacío o
/// demasiado largo (criterio 6).
class MotivoDeRechazoInvalidoException implements Exception {
  const MotivoDeRechazoInvalidoException(this.detalle);

  final String detalle;

  @override
  String toString() => 'MotivoDeRechazoInvalidoException: $detalle';
}

/// Se lanza cuando la ruta ya no está pendiente de esa revisión: otro
/// revisor decidió primero, o ya no existe.
class RutaYaRevisadaException implements Exception {
  const RutaYaRevisadaException();

  @override
  String toString() => 'RutaYaRevisadaException: la ruta ya fue revisada';
}

/// La revisión de las rutas antes de publicarlas (SCRUM-321).
abstract interface class RevisionRutasRepository {
  /// Las rutas que esperan a [etapa], de la más antigua a la más reciente:
  /// la que lleva más tiempo esperando va primero.
  ///
  /// Con su trazado, que es lo que el revisor tiene que mirar.
  Future<List<Ruta>> pendientes(EtapaRevision etapa);

  /// Aprueba o rechaza la ruta [rutaId] en la etapa en que esté, y devuelve
  /// cómo quedó.
  ///
  /// Lanza [RevisionNoPermitidaException] si quien decide no tiene el rol de
  /// esa etapa o es el autor, [MotivoDeRechazoInvalidoException] si rechaza
  /// sin motivo o con uno demasiado largo, y [RutaYaRevisadaException] si la
  /// ruta ya no está pendiente.
  Future<Ruta> decidir(String rutaId, {required bool aprobar, String? motivo});
}

/// Lee de `rutas` y decide con la función `decidir_revision_ruta` (`0036`).
///
/// `rutas` no tiene policy de update: la única forma de cambiar el estado
/// de una ruta desde la app es esa función, que valida el rol y la etapa.
class SupabaseRevisionRutasRepository implements RevisionRutasRepository {
  SupabaseRevisionRutasRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const String tabla = 'rutas';
  static const String funcionDecidir = 'decidir_revision_ruta';

  /// Cuántas rutas pendientes se traen de una vez.
  static const limite = 100;

  static const _columnasConTrazado =
      'id,autor_id,autor_nombre,entrenamiento_id,nombre,descripcion,'
      'distancia_km,estado,motivo_rechazo,fecha_creacion,fecha_publicacion,'
      'trazado';

  /// Quien decide no tiene el rol de la etapa, o es el autor.
  static const _sinPermiso = '42501';

  /// Rechazo sin motivo o con uno demasiado largo.
  static const _restriccionIncumplida = '23514';

  /// La ruta no existe.
  static const _noExiste = 'TZ404';

  /// La ruta ya no está pendiente de nadie.
  static const _yaRevisada = 'TZ409';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  void _exigirSesion() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaRevisarException();
  }

  @override
  Future<List<Ruta>> pendientes(EtapaRevision etapa) async {
    _exigirSesion();

    // El filtro por estado va aunque RLS ya decida qué se puede leer: al
    // administrador, que lo ve todo, le devolvería también lo publicado.
    final filas = await _cliente
        .from(tabla)
        .select(_columnasConTrazado)
        .eq('estado', etapa.estadoPendiente.valorDb)
        .order('fecha_creacion', ascending: true)
        .limit(limite);

    return filas.map(Ruta.desdeSupabase).toList();
  }

  @override
  Future<Ruta> decidir(
    String rutaId, {
    required bool aprobar,
    String? motivo,
  }) async {
    _exigirSesion();

    try {
      final respuesta = await _cliente.rpc(
        funcionDecidir,
        params: {
          'p_ruta_id': rutaId,
          'p_aprobar': aprobar,
          'p_motivo': aprobar ? null : motivo,
        },
      );

      final fila = switch (respuesta) {
        [final Map<String, dynamic> primera, ...] => primera,
        final Map<String, dynamic> unica => unica,
        _ => null,
      };
      if (fila == null || fila['id'] == null) {
        throw const RutaYaRevisadaException();
      }
      return Ruta.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      if (e.code == _sinPermiso) throw const RevisionNoPermitidaException();
      if (e.code == _restriccionIncumplida) {
        throw MotivoDeRechazoInvalidoException(e.message);
      }
      if (e.code == _yaRevisada || e.code == _noExiste) {
        throw const RutaYaRevisadaException();
      }
      rethrow;
    }
  }
}
