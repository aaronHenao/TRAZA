import 'package:flutter/foundation.dart';

/// Campos del formulario de publicación.
///
/// El criterio 2 de SCRUM-323 pide indicar *la corrección necesaria*: por eso
/// los errores se devuelven por campo.
enum CampoPublicacion { titulo, contenido }

/// Cuánto puede medir el título. Los mismos límites están en las
/// restricciones de `publicaciones_foro` (`0020_foro_publicaciones.sql`).
const maxCaracteresTituloPublicacion = 120;

/// Cuánto puede medir el contenido.
const maxCaracteresContenidoPublicacion = 2000;

/// Lo que el usuario lleva escrito, todavía sin validar (SCRUM-345).
@immutable
class BorradorPublicacion {
  const BorradorPublicacion({this.titulo = '', this.contenido = ''});

  final String titulo;
  final String contenido;

  BorradorPublicacion copyWith({String? titulo, String? contenido}) =>
      BorradorPublicacion(
        titulo: titulo ?? this.titulo,
        contenido: contenido ?? this.contenido,
      );

  /// Qué le falta o qué está mal, por campo. Vacío si se puede publicar.
  ///
  /// La tabla repite estas reglas y es la última palabra; aquí existen para
  /// que el usuario sepa qué corregir antes de que la base lo rechace.
  Map<CampoPublicacion, String> get errores {
    final errores = <CampoPublicacion, String>{};

    // Una cadena de espacios no es un título.
    final titulo = this.titulo.trim();
    if (titulo.isEmpty) {
      errores[CampoPublicacion.titulo] = 'Ponle un título a tu publicación.';
    } else if (titulo.length > maxCaracteresTituloPublicacion) {
      errores[CampoPublicacion.titulo] =
          'El título no puede superar $maxCaracteresTituloPublicacion '
          'caracteres.';
    }

    final contenido = this.contenido.trim();
    if (contenido.isEmpty) {
      errores[CampoPublicacion.contenido] =
          'Escribe el contenido de tu publicación.';
    } else if (contenido.length > maxCaracteresContenidoPublicacion) {
      errores[CampoPublicacion.contenido] =
          'El contenido no puede superar $maxCaracteresContenidoPublicacion '
          'caracteres.';
    }

    return errores;
  }

  bool get esValido => errores.isEmpty;

  /// La publicación lista para enviar, o null si el borrador tiene errores.
  ///
  /// Devolver null es lo que impide registrar una publicación inválida: quien
  /// quiera crearla tiene que pasar por aquí.
  NuevaPublicacion? aNuevaPublicacion() {
    if (!esValido) return null;
    return NuevaPublicacion._(
      titulo: titulo.trim(),
      contenido: contenido.trim(),
    );
  }
}

/// Una publicación validada, lista para insertar.
///
/// Solo se obtiene de [BorradorPublicacion.aNuevaPublicacion].
@immutable
class NuevaPublicacion {
  const NuevaPublicacion._({required this.titulo, required this.contenido});

  final String titulo;
  final String contenido;

  /// Lo que manda el cliente. Autor, nombre, estado y fecha los pone la base.
  Map<String, dynamic> aSupabase() => {
    'titulo': titulo,
    'contenido': contenido,
  };

  @override
  bool operator ==(Object other) =>
      other is NuevaPublicacion &&
      other.titulo == titulo &&
      other.contenido == contenido;

  @override
  int get hashCode => Object.hash(titulo, contenido);

  @override
  String toString() => 'NuevaPublicacion($titulo)';
}
