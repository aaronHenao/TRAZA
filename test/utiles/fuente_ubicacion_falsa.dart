import 'dart:async';

import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/ubicacion_service.dart';

/// Fuente de ubicación controlada por la prueba: emite las posiciones
/// que la prueba quiera y cuenta cuántos suscriptores tiene abiertos.
class FuenteUbicacionFalsa implements FuenteUbicacion {
  FuenteUbicacionFalsa() {
    _controlador = StreamController<PuntoGps>.broadcast(
      onListen: () => suscripcionesAbiertas++,
      onCancel: () => suscripcionesAbiertas--,
    );
  }

  int suscripcionesAbiertas = 0;
  ConfiguracionRastreo? ultimaConfiguracion;

  /// Si la ubicación del teléfono está encendida.
  bool servicio = true;

  late final StreamController<PuntoGps> _controlador;

  @override
  Future<bool> servicioActivo() async => servicio;

  @override
  Stream<PuntoGps> posiciones(ConfiguracionRastreo configuracion) {
    ultimaConfiguracion = configuracion;
    return _controlador.stream;
  }

  void emitir(PuntoGps punto) => _controlador.add(punto);

  void fallar(Object error) => _controlador.addError(error);

  Future<void> cerrar() => _controlador.close();
}

/// Punto de prueba en el campus de la Universidad de Medellín.
PuntoGps puntoDePrueba({
  double latitud = 6.2311,
  double longitud = -75.6105,
  double? precisionMetros = 8,
  DateTime? capturadoEn,
}) {
  return PuntoGps(
    latitud: latitud,
    longitud: longitud,
    capturadoEn: capturadoEn ?? DateTime(2026, 1, 1, 8),
    precisionMetros: precisionMetros,
  );
}
