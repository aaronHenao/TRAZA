import 'package:flutter/foundation.dart';

import 'periodicidad_reto.dart';
import 'vigencia_reto.dart';

/// En qué situación está un reto dentro del catálogo.
///
/// Los nombres coinciden con la restricción `estado in ('activo', 'retirado')`
/// de la tabla `retos`.
enum EstadoReto {
  /// Publicado: aparece en el catálogo de los corredores.
  activo,

  /// Dado de baja (SCRUM-157). Deja de ofrecerse, pero la fila sigue ahí para
  /// que el historial y la XP ya otorgada tengan a qué apuntar.
  retirado;

  String get valorDb => name;

  static EstadoReto? desdeDb(String? valor) {
    for (final estado in values) {
      if (estado.valorDb == valor) return estado;
    }
    return null;
  }
}

/// Un reto ya registrado, tal como vive en la tabla `retos`.
///
/// Se diferencia de `NuevoReto` en que este ya tiene id y estado: los pone la
/// base al insertarlo, no el cliente.
@immutable
class Reto {
  const Reto({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.periodicidad,
    required this.metaKm,
    required this.xpOtorgada,
    required this.vigencia,
    required this.estado,
  });

  final String id;
  final String nombre;
  final String descripcion;
  final PeriodicidadReto periodicidad;
  final double metaKm;
  final int xpOtorgada;
  final VigenciaReto vigencia;
  final EstadoReto estado;

  /// SCRUM-145: si aparece en el catálogo de los corredores.
  bool get estaActivo => estado == EstadoReto.activo;

  /// Lee una fila de `retos`.
  ///
  /// Lanza [FormatException] si falta algo o no se entiende. Es a propósito:
  /// las columnas son `not null` con sus restricciones, así que una fila que
  /// no encaje significa que el esquema y esta clase se desalinearon, y eso se
  /// arregla, no se disimula con valores por defecto.
  factory Reto.desdeSupabase(Map<String, dynamic> fila) {
    final periodicidad = PeriodicidadReto.desdeDb(fila['periodicidad'] as String?);
    final estado = EstadoReto.desdeDb(fila['estado'] as String?);
    final id = fila['id'];
    final nombre = fila['nombre'];
    final descripcion = fila['descripcion'];
    final meta = fila['meta_km'];
    final xp = fila['xp_otorgada'];
    final inicio = fila['fecha_inicio'];
    final fin = fila['fecha_fin'];

    if (id is! String ||
        nombre is! String ||
        descripcion is! String ||
        periodicidad == null ||
        estado == null ||
        meta is! num ||
        xp is! num ||
        inicio is! String ||
        fin is! String) {
      throw FormatException('Fila de retos incompleta o inesperada', fila);
    }

    return Reto(
      id: id,
      nombre: nombre,
      descripcion: descripcion,
      periodicidad: periodicidad,
      metaKm: meta.toDouble(),
      xpOtorgada: xp.toInt(),
      vigencia: VigenciaReto(
        inicio: VigenciaReto.desdeTexto(inicio),
        fin: VigenciaReto.desdeTexto(fin),
      ),
      estado: estado,
    );
  }

  @override
  bool operator ==(Object other) => other is Reto && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Reto($nombre, ${periodicidad.valorDb}, ${estado.valorDb})';
}
