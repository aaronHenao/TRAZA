import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/borrador_publicacion.dart';
import '../models/comentario_foro.dart';
import '../models/publicacion_foro.dart';

/// Repositorio del foro que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final foroRepositoryProvider = Provider<ForoRepository>(
  (ref) => SupabaseForoRepository(),
);

/// Quién usa el foro: el id del usuario con la sesión abierta, o null.
///
/// Es una función y no un valor para que siempre diga la sesión de ahora, no
/// la que había cuando se creó el provider. Las pruebas la sustituyen.
final usuarioActualProvider = Provider<String? Function()>(
  (ref) =>
      () => Supabase.instance.client.auth.currentUser?.id,
);

/// Se lanza cuando se intenta usar el foro sin una sesión abierta.
class SesionRequeridaParaForoException implements Exception {
  const SesionRequeridaParaForoException();

  @override
  String toString() =>
      'SesionRequeridaParaForoException: no hay una sesión abierta';
}

/// Se lanza cuando la base rechaza los datos de la publicación.
///
/// No debería ocurrir: `BorradorPublicacion` valida las mismas reglas antes.
/// Si llega aquí, la tabla y la validación de Dart se desalinearon.
class DatosDePublicacionInvalidosException implements Exception {
  const DatosDePublicacionInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDePublicacionInvalidosException: $detalle';
}

/// Se lanza al comentar o editar una publicación que fue eliminada o retenida
/// por la moderación (criterio 3 de SCRUM-324, SCRUM-355).
///
/// Quienes lo impiden son las policies de `comentarios_foro` y
/// `publicaciones_foro`, que exigen que la publicación esté publicada en ese
/// momento: la app puede tener en pantalla una versión vieja.
class PublicacionNoDisponibleException implements Exception {
  const PublicacionNoDisponibleException();

  @override
  String toString() =>
      'PublicacionNoDisponibleException: la publicación ya no está publicada';
}

/// Acceso a las tablas del foro: `publicaciones_foro` (SCRUM-323) y
/// `comentarios_foro` (SCRUM-324).
abstract interface class ForoRepository {
  /// Registra [publicacion] a nombre del usuario de la sesión y devuelve la
  /// fila creada (SCRUM-343).
  ///
  /// Lo que vuelve trae el nombre del autor, el estado y la fecha que puso la
  /// base. El estado es lo que dice si se difundió o quedó retenida.
  Future<PublicacionForo> crear(NuevaPublicacion publicacion);

  /// Lo publicado en el foro, de lo más reciente a lo más antiguo
  /// (SCRUM-346).
  Future<List<PublicacionForo>> publicadas();

  /// Todas las publicaciones, en cualquier estado, para el administrador.
  ///
  /// La policy de `select` solo le deja ver todo al administrador; a un
  /// corredor le devolvería lo publicado y lo suyo.
  Future<List<PublicacionForo>> todasParaModeracion();

  /// La publicación con [id], o null si no existe o el usuario no puede
  /// verla (SCRUM-350).
  ///
  /// Puede volver en cualquier estado: el autor ve lo suyo retenido y el
  /// administrador todo. Si se puede comentar lo decide
  /// [PublicacionForo.admiteComentarios].
  Future<PublicacionForo?> publicacion(String id);

  /// Los comentarios de una publicación, del más antiguo al más reciente,
  /// como se lee una conversación (SCRUM-350).
  Future<List<ComentarioForo>> comentarios(String publicacionId);

  /// Registra [comentario] a nombre del usuario de la sesión y devuelve la
  /// fila creada (SCRUM-350).
  ///
  /// Lanza [PublicacionNoDisponibleException] si la publicación ya no está
  /// publicada.
  Future<ComentarioForo> comentar(NuevoComentario comentario);

  /// Cambia el título y el contenido de la publicación [id] y devuelve cómo
  /// quedó (SCRUM-355).
  ///
  /// Lanza [PublicacionNoDisponibleException] si no es del usuario o ya no
  /// está publicada.
  Future<PublicacionForo> editar(String id, NuevaPublicacion cambios);
}

class SupabaseForoRepository implements ForoRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseForoRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'publicaciones_foro';
  static const _tablaComentarios = 'comentarios_foro';

  /// Las columnas de la publicación más cuántos comentarios tiene, contados
  /// por PostgREST sin traerlos.
  static const _columnas = '*, comentarios_foro(count)';

  /// Suficiente para el foro de un proyecto de curso sin traer la tabla
  /// entera.
  static const limite = 100;

  static const _restriccionIncumplida = '23514';
  static const _rlsDenegado = '42501';

  /// La consulta pidió una fila y no vino ninguna: en un update, la policy
  /// no dejó tocar la fila.
  static const _sinFilas = 'PGRST116';

  /// La publicación ya no existe: la clave foránea no encuentra a quién
  /// apuntar.
  static const _sinReferencia = '23503';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaForoException();
    return id;
  }

  @override
  Future<PublicacionForo> crear(NuevaPublicacion publicacion) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tabla)
          // Ni el nombre del autor ni el estado van: los pone el trigger
          // `publicaciones_foro_preparar`. Si los mandara el cliente,
          // cualquiera publicaría con otro nombre o saltándose la moderación.
          .insert({...publicacion.aSupabase(), 'autor_id': usuarioId})
          .select()
          .single();

      return PublicacionForo.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<PublicacionForo>> publicadas() async {
    _usuarioId();

    // El filtro va aunque RLS ya oculte lo ajeno: el autor también ve lo suyo
    // retenido, y eso no pertenece al foro.
    final filas = await _cliente
        .from(_tabla)
        .select(_columnas)
        .eq('estado', EstadoPublicacion.publicada.valorDb)
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(PublicacionForo.desdeSupabase).toList();
  }

  @override
  Future<List<PublicacionForo>> todasParaModeracion() async {
    _usuarioId();

    final filas = await _cliente
        .from(_tabla)
        .select(_columnas)
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(PublicacionForo.desdeSupabase).toList();
  }

  @override
  Future<PublicacionForo?> publicacion(String id) async {
    _usuarioId();

    final fila = await _cliente
        .from(_tabla)
        .select(_columnas)
        .eq('id', id)
        .maybeSingle();

    return fila == null ? null : PublicacionForo.desdeSupabase(fila);
  }

  @override
  Future<List<ComentarioForo>> comentarios(String publicacionId) async {
    _usuarioId();

    final filas = await _cliente
        .from(_tablaComentarios)
        .select()
        .eq('publicacion_id', publicacionId)
        .order('fecha_creacion', ascending: true)
        .limit(limite);

    return filas.map(ComentarioForo.desdeSupabase).toList();
  }

  @override
  Future<ComentarioForo> comentar(NuevoComentario comentario) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tablaComentarios)
          // El nombre del autor no va: lo pone el trigger.
          .insert({...comentario.aSupabase(), 'autor_id': usuarioId})
          .select()
          .single();

      return ComentarioForo.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // La policy de insert exige que la publicación siga publicada; si fue
      // retenida o eliminada, la fila viola la seguridad a nivel de fila.
      if (e.code == _rlsDenegado || e.code == _sinReferencia) {
        throw const PublicacionNoDisponibleException();
      }
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<PublicacionForo> editar(String id, NuevaPublicacion cambios) async {
    _usuarioId();

    try {
      final fila = await _cliente
          .from(_tabla)
          // Solo el texto. Lo demás, aunque se mandara, lo deja igual el
          // trigger `publicaciones_foro_proteger`.
          .update(cambios.aSupabase())
          .eq('id', id)
          .select(_columnas)
          .single();

      return PublicacionForo.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // Si no es suya o ya no está publicada, la policy de update no deja ver
      // la fila: el update no toca nada y no vuelve ninguna.
      if (e.code == _sinFilas || e.code == _rlsDenegado) {
        throw const PublicacionNoDisponibleException();
      }
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }
}
