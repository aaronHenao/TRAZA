import 'package:flutter/foundation.dart';

/// Cuánto puede medir un comentario. El mismo límite está en la restricción
/// de `comentarios_foro` (`0021_foro_comentarios.sql`).
const maxCaracteresComentario = 500;

/// Un comentario de una publicación del foro, tal como vive en
/// `comentarios_foro` (SCRUM-324).
///
/// El nombre del autor y la fecha los pone la base al insertarlo.
@immutable
class ComentarioForo {
  const ComentarioForo({
    required this.id,
    required this.publicacionId,
    required this.autorId,
    required this.autorNombre,
    required this.contenido,
    required this.fechaCreacion,
  });

  final String id;
  final String publicacionId;
  final String autorId;
  final String autorNombre;
  final String contenido;
  final DateTime fechaCreacion;

  factory ComentarioForo.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final publicacionId = fila['publicacion_id'];
    final autorId = fila['autor_id'];
    final autorNombre = fila['autor_nombre'];
    final contenido = fila['contenido'];
    final fecha = fila['fecha_creacion'];

    if (id is! String ||
        publicacionId is! String ||
        autorId is! String ||
        autorNombre is! String ||
        contenido is! String ||
        fecha is! String) {
      throw FormatException(
        'Fila de comentarios_foro incompleta o inesperada',
        fila,
      );
    }

    return ComentarioForo(
      id: id,
      publicacionId: publicacionId,
      autorId: autorId,
      autorNombre: autorNombre,
      contenido: contenido,
      fechaCreacion: DateTime.parse(fecha).toLocal(),
    );
  }

  @override
  bool operator ==(Object other) => other is ComentarioForo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ComentarioForo($autorNombre: $contenido)';
}

/// Lo que el usuario lleva escrito en la caja de comentario, sin validar
/// (SCRUM-352).
@immutable
class BorradorComentario {
  const BorradorComentario(this.texto);

  final String texto;

  static const vacio = 'El comentario no puede estar vacío.';
  static const muyLargo =
      'El comentario no puede superar $maxCaracteresComentario caracteres.';

  /// Qué está mal, o null si se puede enviar.
  ///
  /// Una cadena de espacios no es un comentario (criterio 2 de SCRUM-324).
  String? get error {
    final limpio = texto.trim();
    if (limpio.isEmpty) return vacio;
    if (limpio.length > maxCaracteresComentario) return muyLargo;
    return null;
  }

  /// El comentario listo para insertar, o null si no es válido.
  NuevoComentario? aNuevoComentario(String publicacionId) {
    if (error != null) return null;
    return NuevoComentario._(
      publicacionId: publicacionId,
      contenido: texto.trim(),
    );
  }
}

/// Un comentario validado, listo para insertar.
///
/// Solo se obtiene de [BorradorComentario.aNuevoComentario].
@immutable
class NuevoComentario {
  const NuevoComentario._({
    required this.publicacionId,
    required this.contenido,
  });

  final String publicacionId;
  final String contenido;

  /// Lo que manda el cliente. Autor, nombre y fecha los pone la base.
  Map<String, dynamic> aSupabase() => {
    'publicacion_id': publicacionId,
    'contenido': contenido,
  };

  @override
  bool operator ==(Object other) =>
      other is NuevoComentario &&
      other.publicacionId == publicacionId &&
      other.contenido == contenido;

  @override
  int get hashCode => Object.hash(publicacionId, contenido);

  @override
  String toString() => 'NuevoComentario($publicacionId: $contenido)';
}
