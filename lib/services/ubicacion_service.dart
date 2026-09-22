import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/punto_gps.dart';

/// Frecuencia y calidad con las que se procesa la ubicación (SCRUM-110).
///
/// El sistema entrega **todas** las lecturas
/// ([distanciaMinimaSistemaMetros] en 0) y el filtrado se hace en Dart.
/// Delegarlo en el `distanceFilter` del SO salía caro: con el usuario
/// quieto Android deja de entregar lecturas y baja el ritmo del GNSS, así
/// que al volver a moverse la app tardaba varios segundos en enterarse
/// (SCRUM-116). Recibiendo todo, el marcador y el detector de reposo
/// reaccionan al instante, y el ruido se descarta aquí:
/// [distanciaMinimaRegistroMetros] para lo que se guarda como recorrido.
class ConfiguracionRastreo {
  const ConfiguracionRastreo({
    this.distanciaMinimaSistemaMetros = 0,
    this.distanciaMinimaRegistroMetros = 5,
    this.altaPrecision = true,
    this.precisionMaximaMetros = 30,
    this.antiguedadMaxima = const Duration(seconds: 30),
    this.enSegundoPlano = true,
  });

  /// Desplazamiento mínimo que se le pide al sistema entre dos lecturas.
  /// `0` = todas las lecturas, que es lo que queremos.
  final int distanciaMinimaSistemaMetros;

  /// Desplazamiento mínimo entre dos puntos del recorrido, en metros.
  /// Por debajo de esto la lectura es jitter del GPS con el usuario
  /// quieto y no se registra: si no, el trazo acumula puntos fantasma.
  final double distanciaMinimaRegistroMetros;

  /// `true` pide la mejor precisión disponible (más batería).
  final bool altaPrecision;

  /// Radio de error máximo aceptado. Una lectura peor que esto (típico
  /// al arrancar bajo techo) pondría el punto a cuadras de distancia,
  /// así que se descarta. `null` = aceptar todo.
  ///
  /// Es el **único** umbral de precisión de la app: `CalculadoraDistancia`
  /// recibe este mismo valor. Cuando eran dos distintos (50 aquí, 25 allá)
  /// las lecturas intermedias movían el marcador sin sumar distancia, y el
  /// usuario veía el punto avanzar con los kilómetros parados (SCRUM-116).
  final double? precisionMaximaMetros;

  /// Edad máxima de una lectura. Al abrir el stream, Android entrega
  /// primero la última posición conocida — que puede ser de hace media
  /// hora y a kilómetros de donde arranca la actividad. `null` = aceptar
  /// todo.
  final Duration? antiguedadMaxima;

  /// Seguir rastreando con la pantalla bloqueada o la app detrás de otra.
  ///
  /// En Android levanta un servicio en primer plano con notificación
  /// persistente (sin eso el sistema corta las lecturas a unas pocas por
  /// hora y puede matar el proceso). En iOS activa las actualizaciones en
  /// segundo plano con el indicador azul del sistema.
  final bool enSegundoPlano;

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
  /// `false` si la ubicación del teléfono está apagada. Es distinto del
  /// permiso: se puede tener concedido y aun así no haber GPS que escuchar.
  Future<bool> servicioActivo();

  /// Stream de posiciones mientras haya alguien suscrito.
  Stream<PuntoGps> posiciones(ConfiguracionRastreo configuracion);
}

/// Texto de la notificación persistente de Android mientras se rastrea.
const String tituloNotificacionRastreo = 'TRAZA · Entrenamiento en curso';
const String textoNotificacionRastreo = 'Registrando tu recorrido';

/// Implementación con `geolocator` (SCRUM-108).
class UbicacionGeolocator implements FuenteUbicacion {
  const UbicacionGeolocator();

  @override
  Future<bool> servicioActivo() => Geolocator.isLocationServiceEnabled();

  @override
  Stream<PuntoGps> posiciones(ConfiguracionRastreo configuracion) async* {
    // Primero una lectura puntual y después el stream continuo.
    //
    // No es solo por entregar el primer fix cuanto antes: geolocator en
    // Android descarta en silencio un getPositionStream que se abra
    // antes de que el plugin termine de enlazar su servicio (ocurre en
    // los primeros ~3 s tras arrancar la app; el stream se queda mudo,
    // sin datos ni error). getCurrentPosition no depende de ese servicio,
    // y cuando resuelve el servicio ya está enlazado.
    yield _aPunto(
      await Geolocator.getCurrentPosition(
        locationSettings: ajustesBasicos(configuracion),
      ),
    );
    yield* Geolocator.getPositionStream(
      locationSettings: ajustesPara(configuracion, defaultTargetPlatform),
    ).map(_aPunto);
  }

  /// Precisión y filtro de distancia, sin nada de segundo plano. Para la
  /// lectura puntual inicial no hace falta levantar ningún servicio.
  static LocationSettings ajustesBasicos(ConfiguracionRastreo configuracion) {
    return LocationSettings(
      accuracy: _precision(configuracion),
      distanceFilter: configuracion.distanciaMinimaSistemaMetros,
    );
  }

  /// Ajustes del stream continuo según la plataforma.
  ///
  /// Con [ConfiguracionRastreo.enSegundoPlano], Android recibe la
  /// notificación del servicio en primer plano y iOS el permiso de seguir
  /// en segundo plano; en cualquier otra plataforma son los básicos.
  static LocationSettings ajustesPara(
    ConfiguracionRastreo configuracion,
    TargetPlatform plataforma,
  ) {
    final precision = _precision(configuracion);
    final distancia = configuracion.distanciaMinimaSistemaMetros;

    switch (plataforma) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: precision,
          distanceFilter: distancia,
          foregroundNotificationConfig: configuracion.enSegundoPlano
              ? const ForegroundNotificationConfig(
                  notificationTitle: tituloNotificacionRastreo,
                  notificationText: textoNotificacionRastreo,
                  notificationChannelName: 'Entrenamiento en curso',
                  // El usuario no puede descartarla mientras dure la
                  // actividad: es lo que mantiene vivo el rastreo.
                  setOngoing: true,
                  // Sin wake lock, con la pantalla apagada el GPS deja de
                  // recibir fixes en varios fabricantes.
                  enableWakeLock: true,
                )
              : null,
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: precision,
          distanceFilter: distancia,
          activityType: ActivityType.fitness,
          allowBackgroundLocationUpdates: configuracion.enSegundoPlano,
          showBackgroundLocationIndicator: configuracion.enSegundoPlano,
          pauseLocationUpdatesAutomatically: false,
        );
      default:
        return ajustesBasicos(configuracion);
    }
  }

  static LocationAccuracy _precision(ConfiguracionRastreo configuracion) =>
      configuracion.altaPrecision
          ? LocationAccuracy.best
          : LocationAccuracy.medium;

  static PuntoGps _aPunto(Position posicion) => PuntoGps(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
        capturadoEn: posicion.timestamp,
        precisionMetros: posicion.accuracy,
      );
}
