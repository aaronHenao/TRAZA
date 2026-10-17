import 'package:flutter/foundation.dart';

/// En qué situación está una publicación o un comentario del foro.
///
/// Los valores coinciden con la restricción `estado in (...)` de
/// `publicaciones_foro` y `comentarios_foro` (`0029_foro_moderacion_ia.sql`).
enum EstadoPublicacion {
  /// Recién escrita: la IA la está analizando (SCRUM-322). Solo la ven su
  /// autor y el administrador.
  enRevision('en_revision'),

  /// Visible para todos en el foro.
  publicada('publicada'),

  /// La IA dudó y la decide el administrador (SCRUM-322). Para el autor
  /// sigue "en revisión".
  pendiente('pendiente'),

  /// La moderación la retiró por spam o contenido ofensivo (SCRUM-322).
  rechazada('rechazada'),

  /// Retirada del foro (SCRUM-242).
  eliminada('eliminada');

  const EstadoPublicacion(this.valorDb);

  final String valorDb;

  /// Todavía no hay veredicto: el autor la ve "en revisión".
  bool get esperaModeracion => this == enRevision || this == pendiente;

  static EstadoPublicacion? desdeDb(String? valor) {
    for (final estado in values) {
      if (estado.valorDb == valor) return estado;
    }
    return null;
  }
}

/// Una publicación del foro, tal como vive en `publicaciones_foro`
/// (SCRUM-323).
///
/// El nombre del autor, si es administrador, el estado y la fecha los pone
/// la base al insertarla, no el cliente.
@immutable
class PublicacionForo {
  const PublicacionForo({
    required this.id,
    required this.autorId,
    required this.autorNombre,
    required this.titulo,
    required this.contenido,
    required this.estado,
    required this.fechaCreacion,
    this.motivoModeracion,
    this.numeroComentarios = 0,
    this.autorEsAdmin = false,
    this.fechaEdicion,
  });

  final String id;
  final String autorId;
  final String autorNombre;
  final String titulo;
  final String contenido;
  final EstadoPublicacion estado;
  final DateTime fechaCreacion;

  /// Por qué la moderación la rechazó o eliminó. Null mientras no haya
  /// rechazo.
  final String? motivoModeracion;

  /// Cuántos comentarios tiene (SCRUM-324). Cero si la consulta no los
  /// contó, como la fila que devuelve el insert.
  final int numeroComentarios;

  /// La escribió el administrador: lleva la insignia "Administrador"
  /// (SCRUM-354).
  final bool autorEsAdmin;

  /// Cuándo se editó por última vez, o null si nunca (SCRUM-355). La pone la
  /// base al cambiar el título o el contenido.
  final DateTime? fechaEdicion;

  /// Si se editó: se avisa junto a la fecha y se puede ver su historial.
  bool get editada => fechaEdicion != null;

  /// Si se le puede comentar: solo a lo publicado (criterio 3 de SCRUM-324).
  bool get admiteComentarios => estado == EstadoPublicacion.publicada;

  /// Si [usuarioId] la puede editar: es suya y sigue publicada (SCRUM-355).
  ///
  /// Lo mismo exige `editar_publicacion_foro`; aquí solo decide si se ofrece
  /// el botón. Que no tenga ya una edición en revisión lo decide quien la
  /// muestra (SCRUM-322).
  bool editablePor(String? usuarioId) =>
      usuarioId != null &&
      usuarioId == autorId &&
      estado == EstadoPublicacion.publicada;

  factory PublicacionForo.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final autorId = fila['autor_id'];
    final autorNombre = fila['autor_nombre'];
    final titulo = fila['titulo'];
    final contenido = fila['contenido'];
    final estado = EstadoPublicacion.desdeDb(fila['estado'] as String?);
    final fecha = fila['fecha_creacion'];
    final motivo = fila['motivo_moderacion'];
    final edicion = fila['fecha_edicion'];

    if (id is! String ||
        autorId is! String ||
        autorNombre is! String ||
        titulo is! String ||
        contenido is! String ||
        estado == null ||
        fecha is! String ||
        (motivo != null && motivo is! String) ||
        (edicion != null && edicion is! String)) {
      throw FormatException(
        'Fila de publicaciones_foro incompleta o inesperada',
        fila,
      );
    }

    return PublicacionForo(
      id: id,
      autorId: autorId,
      autorNombre: autorNombre,
      titulo: titulo,
      contenido: contenido,
      estado: estado,
      fechaCreacion: DateTime.parse(fecha).toLocal(),
      motivoModeracion: motivo as String?,
      numeroComentarios: _conteo(fila['comentarios_foro']),
      autorEsAdmin: fila['autor_es_admin'] == true,
      fechaEdicion: edicion is String
          ? DateTime.parse(edicion).toLocal()
          : null,
    );
  }

  /// PostgREST devuelve `comentarios_foro(count)` como `[{"count": n}]`.
  static int _conteo(Object? embebido) {
    if (embebido case [{'count': final num n}, ...]) return n.toInt();
    return 0;
  }

  @override
  bool operator ==(Object other) => other is PublicacionForo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PublicacionForo($titulo, ${estado.valorDb})';
}
