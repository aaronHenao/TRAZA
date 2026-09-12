import 'package:geolocator/geolocator.dart';

import '../models/punto_gps.dart';

/// Parámetros con los que se abre el stream de posiciones.
///
/// Los valores definitivos (cada cuántos metros se procesa una lectura,
/// con qué precisión) son tema de SCRUM-110; aquí solo se deja el punto
/// de configuración con un valor provisional.
class ConfiguracionRastreo {
  const ConfiguracionRastreo({
    this.distanciaMinimaMetros = 0,
    this.altaPrecision = true,
  });

  /// Desplazamiento mínimo entre dos lecturas para que el sistema
  /// entregue una nueva. `0` = todas las lecturas.
  final int distanciaMinimaMetros;

  /// `true` pide la mejor precisión disponible (más batería).
  final bool altaPrecision;
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
