import 'package:flutter/foundation.dart';

/// Un recorrido guardado en el teléfono y en qué va su sincronización con
/// Supabase (Drift, Desarrollo Móvil).
///
/// Es lo que mostrará la pantalla de sincronización: si falta subir algo,
/// por qué falló la última vez y si la base lo rechazó.
@immutable
class RecorridoLocal {
  const RecorridoLocal({
    required this.entrenamientoId,
    required this.usuarioId,
    required this.actualizadoEn,
    required this.pendienteSync,
    required this.ultimoError,
    required this.rechazado,
    required this.puntosSinEnviar,
  });

  /// Lo que se anota cuando la base no acepta el recorrido (42501 o 23503).
  /// Reintentarlo no lo arregla: queda para que la persona lo descarte.
  static const motivoRechazado =
      'La base no aceptó el recorrido: el entrenamiento ya no existe o es de '
      'otra cuenta.';

  /// Lo que se anota ante cualquier otro fallo, casi siempre la red.
  static const motivoSinEnviar =
      'No se pudo enviar. Se vuelve a intentar al abrir la app con conexión.';

  /// El id del entrenamiento en Supabase: identifica el recorrido aquí y
  /// allá, y no cambia.
  final String entrenamientoId;

  /// La cuenta dueña. Null si vino de los archivos de antes de Drift, que
  /// no la guardaban.
  final String? usuarioId;

  final DateTime actualizadoEn;

  /// Si queda algo por subir.
  final bool pendienteSync;

  /// Por qué falló el último intento, o null si no ha fallado.
  final String? ultimoError;

  /// Si la base lo rechazó: ya no se reintenta solo.
  final bool rechazado;

  final int puntosSinEnviar;

  @override
  bool operator ==(Object other) =>
      other is RecorridoLocal &&
      other.entrenamientoId == entrenamientoId &&
      other.usuarioId == usuarioId &&
      other.actualizadoEn == actualizadoEn &&
      other.pendienteSync == pendienteSync &&
      other.ultimoError == ultimoError &&
      other.rechazado == rechazado &&
      other.puntosSinEnviar == puntosSinEnviar;

  @override
  int get hashCode => Object.hash(
    entrenamientoId,
    usuarioId,
    actualizadoEn,
    pendienteSync,
    ultimoError,
    rechazado,
    puntosSinEnviar,
  );

  @override
  String toString() =>
      'RecorridoLocal($entrenamientoId, $puntosSinEnviar sin enviar'
      '${rechazado ? ', rechazado' : ''})';
}
