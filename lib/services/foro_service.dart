import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/borrador_publicacion.dart';
import '../models/publicacion_foro.dart';

/// Repositorio del foro que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final foroRepositoryProvider = Provider<ForoRepository>(
  (ref) => SupabaseForoRepository(),
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

/// Acceso a la tabla `publicaciones_foro` (SCRUM-323).
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

  /// Suficiente para el foro de un proyecto de curso sin traer la tabla
  /// entera.
  static const limite = 100;

  static const _restriccionIncumplida = '23514';

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
        .select()
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
        .select()
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(PublicacionForo.desdeSupabase).toList();
  }
}
