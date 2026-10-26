import 'package:flutter/foundation.dart';

import 'ruta.dart';

/// Una ruta publicada con a cuántos kilómetros le queda al usuario
/// (SCRUM-246).
///
/// La distancia la calcula la base (`rutas_cercanas`, 0037) en línea recta
/// hasta donde arranca la ruta, y es lo que ordena Explorar rutas. No es lo
/// que mide la ruta: eso es `ruta.distanciaKm`.
@immutable
class RutaCercana {
  const RutaCercana({required this.ruta, required this.distanciaKm});

  final Ruta ruta;

  /// Kilómetros en línea recta desde el usuario hasta el inicio de la ruta.
  final double distanciaKm;

  /// Lee una fila de `rutas_cercanas`: las columnas de la ruta más
  /// `distancia_usuario_km`.
  ///
  /// Lanza [FormatException] si falta la distancia: la función siempre la
  /// devuelve, así que una fila sin ella significa que la consulta y esta
  /// clase se desalinearon.
  factory RutaCercana.desdeSupabase(Map<String, dynamic> fila) {
    final distancia = fila['distancia_usuario_km'];
    if (distancia is! num) {
      throw FormatException(
        'rutas_cercanas devolvió una fila sin distancia al usuario',
        fila,
      );
    }

    return RutaCercana(
      ruta: Ruta.desdeSupabase(fila),
      distanciaKm: distancia.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RutaCercana &&
      other.ruta == ruta &&
      other.distanciaKm == distanciaKm;

  @override
  int get hashCode => Object.hash(ruta, distanciaKm);

  @override
  String toString() => 'RutaCercana(${ruta.nombre}, a $distanciaKm km)';
}
