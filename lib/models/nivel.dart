import 'package:flutter/foundation.dart';

/// Un nivel ya registrado, tal como vive en la tabla `niveles`.
///
/// Se diferencia de `NuevoNivel` en que este ya tiene id: lo pone la base al
/// insertarlo, no el cliente.
@immutable
class Nivel {
  const Nivel({
    required this.id,
    required this.nombre,
    required this.umbralExperiencia,
  });

  final String id;
  final String nombre;

  /// Experiencia acumulada con la que se entra al nivel. El nivel va desde
  /// aquí hasta el umbral del siguiente.
  final int umbralExperiencia;

  /// Lee una fila de `niveles`.
  ///
  /// Lanza [FormatException] si falta algo o no se entiende. Es a propósito:
  /// las columnas son `not null` con sus restricciones, así que una fila que
  /// no encaje significa que el esquema y esta clase se desalinearon, y eso se
  /// arregla, no se disimula con valores por defecto.
  factory Nivel.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final nombre = fila['nombre'];
    final umbral = fila['umbral_experiencia'];

    if (id is! String || nombre is! String || umbral is! num) {
      throw FormatException('Fila de niveles incompleta o inesperada', fila);
    }

    return Nivel(id: id, nombre: nombre, umbralExperiencia: umbral.toInt());
  }

  @override
  bool operator ==(Object other) => other is Nivel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Nivel($nombre, $umbralExperiencia XP)';
}
