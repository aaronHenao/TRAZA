import 'package:flutter/foundation.dart';

/// Cómo se leía una publicación antes de una edición, tal como la guarda
/// `versiones_publicacion_foro` (SCRUM-355).
@immutable
class VersionPublicacion {
  const VersionPublicacion({
    required this.id,
    required this.titulo,
    required this.contenido,
    required this.vigenteDesde,
  });

  final String id;
  final String titulo;
  final String contenido;

  /// Desde cuándo se leía así: la creación o la edición anterior.
  final DateTime vigenteDesde;

  factory VersionPublicacion.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final titulo = fila['titulo'];
    final contenido = fila['contenido'];
    final desde = fila['vigente_desde'];

    if (id is! String ||
        titulo is! String ||
        contenido is! String ||
        desde is! String) {
      throw FormatException(
        'Fila de versiones_publicacion_foro incompleta o inesperada',
        fila,
      );
    }

    return VersionPublicacion(
      id: id,
      titulo: titulo,
      contenido: contenido,
      vigenteDesde: DateTime.parse(desde).toLocal(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VersionPublicacion && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VersionPublicacion($titulo)';
}
