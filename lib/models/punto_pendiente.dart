import 'package:flutter/foundation.dart';

import 'punto_gps.dart';

/// Un punto del recorrido esperando a que la base lo acepte (SCRUM-292).
///
/// Es una fila de `puntos_gps` ya numerada: lleva lo que se guarda allí y
/// nada más. La precisión y la velocidad de [PuntoGps] no entran, porque la
/// tabla no las tiene y esto se escribe en disco una vez por punto.
///
/// El [orden] y el [tramo] se deciden al capturar el punto, no al enviarlo:
/// los lotes salen poco a poco y cada uno tiene que conservar su sitio en el
/// recorrido aunque se envíe mucho después.
@immutable
class PuntoPendiente {
  const PuntoPendiente({
    required this.latitud,
    required this.longitud,
    required this.capturadoEn,
    required this.orden,
    required this.tramo,
  });

  PuntoPendiente.de(PuntoGps punto, {required this.orden, required this.tramo})
    : latitud = punto.latitud,
      longitud = punto.longitud,
      capturadoEn = punto.capturadoEn;

  final double latitud;
  final double longitud;
  final DateTime capturadoEn;

  /// Su `orden_secuencia`: la posición en el recorrido, desde 0. Junto al
  /// entrenamiento identifica el punto, y es lo que deja reenviar un lote
  /// sin duplicarlo (índice único de `0053`).
  final int orden;

  /// Su `tramo`: 0 hasta la primera pausa, 1 hasta la siguiente... (0007).
  final int tramo;

  PuntoGps get punto =>
      PuntoGps(latitud: latitud, longitud: longitud, capturadoEn: capturadoEn);

  /// Una línea del archivo del recorrido. Las claves son cortas a propósito:
  /// se escribe una línea por punto y el archivo vive en el teléfono.
  Map<String, Object> aJson() => {
    'la': latitud,
    'lo': longitud,
    't': capturadoEn.toUtc().toIso8601String(),
    'o': orden,
    'tr': tramo,
  };

  /// Lee una línea, o devuelve null si no se entiende.
  ///
  /// Null en vez de excepción a propósito: si la app muere a mitad de una
  /// escritura, la última línea queda cortada. Perder ese punto es
  /// aceptable; perder el recorrido entero por no saber leerlo, no.
  static PuntoPendiente? desdeJson(Object? json) {
    if (json case {
      'la': final num latitud,
      'lo': final num longitud,
      't': final String capturadoEn,
      'o': final int orden,
      'tr': final int tramo,
    }) {
      final fecha = DateTime.tryParse(capturadoEn);
      if (fecha == null || orden < 0 || tramo < 0) return null;
      return PuntoPendiente(
        latitud: latitud.toDouble(),
        longitud: longitud.toDouble(),
        capturadoEn: fecha.toLocal(),
        orden: orden,
        tramo: tramo,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PuntoPendiente &&
      other.latitud == latitud &&
      other.longitud == longitud &&
      other.capturadoEn == capturadoEn &&
      other.orden == orden &&
      other.tramo == tramo;

  @override
  int get hashCode => Object.hash(latitud, longitud, capturadoEn, orden, tramo);

  @override
  String toString() => 'PuntoPendiente(#$orden, tramo $tramo)';
}
