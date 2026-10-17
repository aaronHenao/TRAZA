import 'package:flutter/foundation.dart';

/// Una insignia del catálogo y, si el corredor ya la ganó, cuándo
/// (SCRUM-193).
///
/// La otorga el trigger de `0010_insignias.sql` al llegar a [xpRequerida]; la
/// app solo la lee.
@immutable
class Insignia {
  const Insignia({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
    required this.xpRequerida,
    this.obtenidaEl,
  });

  final String id;
  final String nombre;
  final String descripcion;

  /// Clave del dibujo, no un nombre de archivo: `SeccionInsignias` la traduce
  /// a un icono y usa uno genérico si no la conoce.
  final String icono;

  /// XP acumulada con la que se gana.
  final int xpRequerida;

  /// Null mientras no la haya ganado.
  final DateTime? obtenidaEl;

  bool get obtenida => obtenidaEl != null;

  /// Lee una fila de `insignias` con `insignias_usuario(fecha_obtencion)`
  /// embebido. RLS solo deja ver las del corredor, así que esa lista trae una
  /// fila si ya la ganó y ninguna si no.
  ///
  /// Lanza [FormatException] si la fila no encaja con el esquema, igual que
  /// `Nivel.desdeSupabase`: eso se arregla, no se disimula.
  factory Insignia.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final nombre = fila['nombre'];
    final descripcion = fila['descripcion'];
    final icono = fila['icono'];
    final xpRequerida = fila['xp_requerida'];

    if (id is! String ||
        nombre is! String ||
        descripcion is! String ||
        icono is! String ||
        xpRequerida is! num) {
      throw FormatException('Fila de insignias incompleta o inesperada', fila);
    }

    return Insignia(
      id: id,
      nombre: nombre,
      descripcion: descripcion,
      icono: icono,
      xpRequerida: xpRequerida.toInt(),
      obtenidaEl: _fechaDeObtencion(fila),
    );
  }

  /// La fecha de la obtención embebida, o null si no hay ninguna.
  /// `fecha_obtencion` es `not null`: una obtención sin fecha es un desajuste.
  static DateTime? _fechaDeObtencion(Map<String, dynamic> fila) {
    final obtenciones = fila['insignias_usuario'];
    if (obtenciones is! List || obtenciones.isEmpty) return null;

    final obtencion = obtenciones.first;
    final fecha = obtencion is Map ? obtencion['fecha_obtencion'] : null;
    if (fecha is! String) {
      throw FormatException('Obtención de insignia inesperada', fila);
    }
    return DateTime.parse(fecha);
  }

  @override
  bool operator ==(Object other) =>
      other is Insignia &&
      other.id == id &&
      other.nombre == nombre &&
      other.descripcion == descripcion &&
      other.icono == icono &&
      other.xpRequerida == xpRequerida &&
      other.obtenidaEl == obtenidaEl;

  @override
  int get hashCode =>
      Object.hash(id, nombre, descripcion, icono, xpRequerida, obtenidaEl);

  @override
  String toString() =>
      'Insignia($nombre, $xpRequerida XP${obtenida ? ', obtenida' : ''})';
}
