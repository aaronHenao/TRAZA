import 'package:flutter/foundation.dart';

import 'tipo_actividad.dart';

/// Lo que el flujo de inicio necesita para arrancar un entrenamiento del tipo
/// que el usuario eligió en los chips (SCRUM-93).
///
/// Hoy lleva lo único que la base de datos asocia a un tipo de actividad: su
/// id y su nombre. Si más adelante los tipos tuvieran ajustes propios (por
/// ejemplo, cada cuánto registrar la ubicación), este es el lugar para
/// agregarlos.
@immutable
class ConfiguracionInicio {
  const ConfiguracionInicio({
    required this.tipoActividadId,
    required this.nombreActividad,
  });

  /// Va a `entrenamientos.tipo_actividad_id` al crear el entrenamiento
  /// (SCRUM-99).
  final String tipoActividadId;

  /// Lo que muestra la pantalla del entrenamiento en curso
  /// (`TrackingScreen.nombreActividad`).
  final String nombreActividad;

  /// La configuración para iniciar con [tipo], o null si no se puede:
  /// - no hay ningún tipo elegido, o
  /// - el tipo viene del catálogo local (no hay sesión) y no tiene id. La
  ///   tabla `entrenamientos` exige `tipo_actividad_id` y su RLS exige sesión,
  ///   así que la base rechazaría ese entrenamiento.
  static ConfiguracionInicio? para(TipoActividad? tipo) {
    if (tipo == null) return null;
    final id = tipo.id;
    if (id == null) return null;
    return ConfiguracionInicio(
      tipoActividadId: id,
      nombreActividad: tipo.nombre,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConfiguracionInicio &&
      other.tipoActividadId == tipoActividadId &&
      other.nombreActividad == nombreActividad;

  @override
  int get hashCode => Object.hash(tipoActividadId, nombreActividad);

  @override
  String toString() =>
      'ConfiguracionInicio($nombreActividad, id: $tipoActividadId)';
}
