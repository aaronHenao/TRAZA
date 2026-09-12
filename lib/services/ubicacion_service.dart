import 'package:geolocator/geolocator.dart';

import '../models/punto_gps.dart';

/// Frecuencia y calidad con las que se procesa la ubicación (SCRUM-110).
///
/// Se filtra por distancia, no por tiempo: corriendo a 12 km/h (~3 m/s)
/// llega una lectura cada 1-2 s, y parado no llega ninguna. Sin ese
/// filtro el GPS "baila" 2-3 m en reposo y el recorrido acumula puntos
/// fantasma.
class ConfiguracionRastreo {
  const ConfiguracionRastreo({
    this.distanciaMinimaMetros = 5,
    this.altaPrecision = true,
    this.precisionMaximaMetros = 50,
    this.antiguedadMaxima = const Duration(seconds: 30),
  });

  /// Desplazamiento mínimo entre dos lecturas para que el sistema
  /// entregue una nueva. `0` = todas las lecturas.
  final int distanciaMinimaMetros;

  /// `true` pide la mejor precisión disponible (más batería).
  final bool altaPrecision;

  /// Radio de error máximo aceptado. Una lectura peor que esto (típico
  /// al arrancar bajo techo) pondría el punto a cuadras de distancia,
  /// así que se descarta. `null` = aceptar todo.
  final double? precisionMaximaMetros;

  /// Edad máxima de una lectura. Al abrir el stream, Android entrega
  /// primero la última posición conocida — que puede ser de hace media
  /// hora y a kilómetros de donde arranca la actividad. `null` = aceptar
  /// todo.
  final Duration? antiguedadMaxima;

  /// `true` si la lectura es lo bastante precisa y reciente para usarla.
  bool acepta(PuntoGps punto, {required DateTime ahora}) {
    return _precisionAceptable(punto) && _recienteA(punto, ahora);
  }

  bool _precisionAceptable(PuntoGps punto) {
    final maxima = precisionMaximaMetros;
    final precision = punto.precisionMetros;
    if (maxima == null || precision == null) return true;
    return precision <= maxima;
  }

  bool _recienteA(PuntoGps punto, DateTime ahora) {
    final maxima = antiguedadMaxima;
    if (maxima == null) return true;
    // Una marca "en el futuro" (relojes desfasados) no es una lectura vieja.
    return ahora.difference(punto.capturadoEn) <= maxima;
  }
}

/// De dónde salen las posiciones del usuario.
///
/// Da por hecho que el permiso de ubicación ya fue concedido (es
/// precondición de la HU; pedirlo es responsabilidad de la HU de
/// permisos). La app usa [UbicacionGeolocator]; las pruebas inyectan
/// una fuente falsa que emite las posiciones que la prueba quiera.
abstract class FuenteUbicacion {
  /// Stream de posiciones mientras haya alguien suscrito.
  Stream<PuntoGps> posiciones(ConfiguracionRastreo configuracion);
}

/// Implementación con `geolocator` (SCRUM-108).
class UbicacionGeolocator implements FuenteUbicacion {
  const UbicacionGeolocator();

  @override
  Stream<PuntoGps> posiciones(ConfiguracionRastreo configuracion) async* {
    final ajustes = LocationSettings(
      accuracy: configuracion.altaPrecision
          ? LocationAccuracy.best
          : LocationAccuracy.medium,
      distanceFilter: configuracion.distanciaMinimaMetros,
    );

    // Primero una lectura puntual y después el stream continuo.
    //
    // No es solo por entregar el primer fix cuanto antes: geolocator en
    // Android descarta en silencio un getPositionStream que se abra
    // antes de que el plugin termine de enlazar su servicio (ocurre en
    // los primeros ~3 s tras arrancar la app; el stream se queda mudo,
    // sin datos ni error). getCurrentPosition no depende de ese servicio,
    // y cuando resuelve el servicio ya está enlazado.
    yield _aPunto(
      await Geolocator.getCurrentPosition(locationSettings: ajustes),
    );
    yield* Geolocator.getPositionStream(locationSettings: ajustes).map(_aPunto);
  }

  static PuntoGps _aPunto(Position posicion) => PuntoGps(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        capturadoEn: posicion.timestamp,
        precisionMetros: posicion.accuracy,
      );
}
