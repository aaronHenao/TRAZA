import 'package:flutter/foundation.dart';

import 'publicacion_foro.dart';

/// Cuánto puede medir un comentario. El mismo límite está en la restricción
/// de `comentarios_foro` (`0021_foro_comentarios.sql`).
const maxCaracteresComentario = 500;

/// Un comentario de una publicación del foro, tal como vive en
/// `comentarios_foro` (SCRUM-324).
///
/// El nombre del autor, si es administrador y la fecha los pone la base al
/// insertarlo.
@immutable
class ComentarioForo {
  const ComentarioForo({
    required this.id,
    required this.publicacionId,
    required this.autorId,
    required this.autorNombre,
    required this.contenido,
    required this.fechaCreacion,
    this.autorEsAdmin = false,
    this.fechaEdicion,
    this.estado = EstadoPublicacion.publicada,
    this.motivoModeracion,
  });

  final String id;
  final String publicacionId;
  final String autorId;
  final String autorNombre;
  final String contenido;
  final DateTime fechaCreacion;

  /// Lo escribió el administrador: lleva la insignia "Administrador".
  final bool autorEsAdmin;

  /// Cuándo se editó por última vez, o null si nunca (SCRUM-356). La pone la
  /// base al cambiar el contenido.
  final DateTime? fechaEdicion;

  /// Pasa por la misma moderación que las publicaciones (SCRUM-322). Los
  /// demás solo ven los publicados; el autor ve los suyos en cualquier
  /// estado.
  final EstadoPublicacion estado;

  /// Por qué la moderación lo rechazó. Null mientras no haya rechazo.
  final String? motivoModeracion;

  /// Si se editó: se avisa junto a la fecha.
  bool get editado => fechaEdicion != null;

  /// Si [usuarioId] lo puede editar: es suyo y está publicado (SCRUM-356).
  ///
  /// Que la publicación siga publicada lo decide quien lo muestra;
  /// `editar_comentario_foro` exige las dos cosas.
  bool editablePor(String? usuarioId) =>
      usuarioId != null &&
      usuarioId == autorId &&
      estado == EstadoPublicacion.publicada;

  factory ComentarioForo.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final publicacionId = fila['publicacion_id'];
    final autorId = fila['autor_id'];
    final autorNombre = fila['autor_nombre'];
    final contenido = fila['contenido'];
    final fecha = fila['fecha_creacion'];
    final edicion = fila['fecha_edicion'];
    // Antes de 0035 la columna no existía: todo estaba publicado.
    final estado = EstadoPublicacion.desdeDb(
      fila['estado'] as String? ?? EstadoPublicacion.publicada.valorDb,
    );
    final motivo = fila['motivo_moderacion'];

    if (id is! String ||
        publicacionId is! String ||
        autorId is! String ||
        autorNombre is! String ||
        contenido is! String ||
        fecha is! String ||
        (edicion != null && edicion is! String) ||
        estado == null ||
        (motivo != null && motivo is! String)) {
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
      autorEsAdmin: fila['autor_es_admin'] == true,
      fechaEdicion: edicion is String
          ? DateTime.parse(edicion).toLocal()
          : null,
      estado: estado,
      motivoModeracion: motivo as String?,
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
