import 'package:flutter/foundation.dart';

/// Una lectura de ubicación durante el entrenamiento.
///
/// Refleja las columnas de `puntos_gps` que produce el GPS (`latitud`,
/// `longitud`, `capturado_en`). `entrenamiento_id` y `orden_secuencia`
/// se asignan al persistir el punto (SCRUM-110), no al capturarlo.
/// Sin altitud, a propósito.
@immutable
class PuntoGps {
  const PuntoGps({
    required this.latitud,
    required this.longitud,
    required this.capturadoEn,
    this.precisionMetros,
  });

  final double latitud;
  final double longitud;

  /// Instante en que el dispositivo tomó la lectura.
  final DateTime capturadoEn;

  /// Radio de error estimado por el GPS, en metros. `null` si la
  /// plataforma no lo reporta.
  final double? precisionMetros;

  @override
  bool operator ==(Object other) =>
      other is PuntoGps &&
      other.latitud == latitud &&
      other.longitud == longitud &&
      other.capturadoEn == capturadoEn &&
      other.precisionMetros == precisionMetros;

  @override
  int get hashCode =>
      Object.hash(latitud, longitud, capturadoEn, precisionMetros);

  @override
  String toString() =>
      'PuntoGps($latitud, $longitud, ${capturadoEn.toIso8601String()})';
}
