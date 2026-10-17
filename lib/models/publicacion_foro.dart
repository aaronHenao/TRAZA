import 'package:flutter/foundation.dart';

/// En qué situación está una publicación del foro.
///
/// Los nombres coinciden con la restricción `estado in (...)` de la tabla
/// `publicaciones_foro` (`0020_foro_publicaciones.sql`).
enum EstadoPublicacion {
  /// Visible para todos en el foro.
  publicada,

  /// Detenida por la moderación antes de difundirse (criterio 3 de
  /// SCRUM-323). Solo la ven su autor y el administrador. Hoy ninguna
  /// publicación llega aquí: la moderación de la IA todavía no existe.
  retenida,

  /// Retirada del foro (SCRUM-242).
  eliminada;

  String get valorDb => name;

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
  });

  final String id;
  final String autorId;
  final String autorNombre;
  final String titulo;
  final String contenido;
  final EstadoPublicacion estado;
  final DateTime fechaCreacion;

  /// Por qué la moderación la retuvo o eliminó. Null mientras esté publicada.
  final String? motivoModeracion;

  /// Cuántos comentarios tiene (SCRUM-324). Cero si la consulta no los
  /// contó, como la fila que devuelve el insert.
  final int numeroComentarios;

  /// La escribió el administrador: lleva la insignia "Administrador"
  /// (SCRUM-354).
  final bool autorEsAdmin;

  /// Si se le puede comentar: solo a lo publicado (criterio 3 de SCRUM-324).
  bool get admiteComentarios => estado == EstadoPublicacion.publicada;

  factory PublicacionForo.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final autorId = fila['autor_id'];
    final autorNombre = fila['autor_nombre'];
    final titulo = fila['titulo'];
    final contenido = fila['contenido'];
    final estado = EstadoPublicacion.desdeDb(fila['estado'] as String?);
    final fecha = fila['fecha_creacion'];
    final motivo = fila['motivo_moderacion'];

    if (id is! String ||
        autorId is! String ||
        autorNombre is! String ||
        titulo is! String ||
        contenido is! String ||
        estado == null ||
        fecha is! String ||
        (motivo != null && motivo is! String)) {
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
