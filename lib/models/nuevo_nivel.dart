import 'package:flutter/foundation.dart';

/// Un nivel validado, listo para registrar.
///
/// Que exista una instancia significa que sus datos ya pasaron las reglas: lo
/// construye el borrador del formulario (SCRUM-181), igual que `NuevoReto` con
/// el suyo.
@immutable
class NuevoNivel {
  const NuevoNivel({required this.nombre, required this.umbralExperiencia});

  final String nombre;
  final int umbralExperiencia;

  /// Las columnas de `niveles` tal como las espera Supabase.
  ///
  /// `creado_por` no va aquí: lo pone el repositorio con la cuenta que tiene
  /// la sesión abierta, no el formulario.
  Map<String, dynamic> aSupabase() => {
    'nombre': nombre,
    'umbral_experiencia': umbralExperiencia,
  };

  @override
  bool operator ==(Object other) =>
      other is NuevoNivel &&
      other.nombre == nombre &&
      other.umbralExperiencia == umbralExperiencia;

  @override
  int get hashCode => Object.hash(nombre, umbralExperiencia);

  @override
  String toString() => 'NuevoNivel($nombre, $umbralExperiencia XP)';
}
