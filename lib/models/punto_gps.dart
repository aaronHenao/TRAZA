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
    this.velocidadMps,
    this.precisionVelocidadMps,
  });

  final double latitud;
  final double longitud;

  /// Instante en que el dispositivo tomó la lectura.
  final DateTime capturadoEn;

  /// Radio de error estimado por el GPS, en metros. `null` si la
  /// plataforma no lo reporta.
  final double? precisionMetros;

  /// Velocidad sobre el suelo que midió el propio GPS, en m/s, o `null` si
  /// la plataforma no la reporta.
  ///
  /// El receptor la calcula por efecto Doppler, no restando posiciones, así
  /// que es fiable aunque la posición tenga 30-40 m de error: es lo que
  /// permite medir el ritmo y la distancia de alguien caminando con un GPS
  /// mediocre (SCRUM-116). No se guarda en `puntos_gps`.
  final double? velocidadMps;

  /// Margen de error de [velocidadMps], en m/s. `null` si no se reporta.
  final double? precisionVelocidadMps;

  /// `true` si [otro] está exactamente en la misma latitud y longitud.
  bool mismaCoordenadaQue(PuntoGps? otro) =>
      otro != null && otro.latitud == latitud && otro.longitud == longitud;

  @override
  bool operator ==(Object other) =>
      other is PuntoGps &&
      other.latitud == latitud &&
      other.longitud == longitud &&
      other.capturadoEn == capturadoEn &&
      other.precisionMetros == precisionMetros &&
      other.velocidadMps == velocidadMps &&
      other.precisionVelocidadMps == precisionVelocidadMps;

  @override
  int get hashCode => Object.hash(
    latitud,
    longitud,
    capturadoEn,
    precisionMetros,
    velocidadMps,
    precisionVelocidadMps,
  );

  @override
  String toString() =>
      'PuntoGps($latitud, $longitud, ${capturadoEn.toIso8601String()})';
}
