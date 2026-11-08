import 'package:flutter/foundation.dart';

import 'ruta.dart';

/// Una ruta publicada que el administrador eligió para el mapa de
/// progresión, con su lugar en el camino (rutas oficiales, etapa 1).
///
/// No copia la ruta: ser oficial no cambia su estado, su autor ni su
/// trazado. Solo dice en qué posición va.
@immutable
class RutaOficial {
  const RutaOficial({required this.posicion, required this.ruta});

  /// Fila de `rutas_oficiales` con su ruta embebida bajo `ruta`
  /// (`0058_rutas_oficiales.sql`).
  factory RutaOficial.desdeSupabase(Map<String, dynamic> fila) {
    final posicion = fila['posicion'];
    final ruta = fila['ruta'];
    if (posicion is! int || ruta is! Map) {
      throw FormatException('Fila de rutas_oficiales inesperada', fila);
    }
    return RutaOficial(
      posicion: posicion,
      ruta: Ruta.desdeSupabase(Map<String, dynamic>.from(ruta)),
    );
  }

  /// 1 es la primera del camino.
  final int posicion;
  final Ruta ruta;

  @override
  bool operator ==(Object other) =>
      other is RutaOficial &&
      other.posicion == posicion &&
      other.ruta.id == ruta.id;

  @override
  int get hashCode => Object.hash(posicion, ruta.id);

  @override
  String toString() => 'RutaOficial($posicion, ${ruta.nombre})';
}
