import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:traza/services/ubicacion_service.dart';

void main() {
  group('UbicacionGeolocator.ajustesPara', () {
    test('en Android levanta el servicio en primer plano con notificación', () {
      final ajustes = UbicacionGeolocator.ajustesPara(
        const ConfiguracionRastreo(),
        TargetPlatform.android,
      );

      expect(ajustes, isA<AndroidSettings>());
      final android = ajustes as AndroidSettings;
      expect(android.accuracy, LocationAccuracy.best);
      // Todas las lecturas, una por segundo: el filtro de ruido es de la
      // app (SCRUM-116).
      expect(android.distanceFilter, 0);
      expect(android.intervalDuration, const Duration(seconds: 1));

      final notificacion = android.foregroundNotificationConfig!;
      expect(notificacion.notificationTitle, tituloNotificacionRastreo);
      expect(notificacion.notificationText, textoNotificacionRastreo);
      expect(notificacion.setOngoing, isTrue);
      expect(notificacion.enableWakeLock, isTrue);
    });

    test('en Android sin segundo plano no hay servicio ni notificación', () {
      final ajustes =
          UbicacionGeolocator.ajustesPara(
                const ConfiguracionRastreo(enSegundoPlano: false),
                TargetPlatform.android,
              )
              as AndroidSettings;

      expect(ajustes.foregroundNotificationConfig, isNull);
    });

    test('en iOS permite seguir en segundo plano como actividad física', () {
      final ajustes = UbicacionGeolocator.ajustesPara(
        const ConfiguracionRastreo(),
        TargetPlatform.iOS,
      );

      expect(ajustes, isA<AppleSettings>());
      final ios = ajustes as AppleSettings;
      expect(ios.allowBackgroundLocationUpdates, isTrue);
      expect(ios.showBackgroundLocationIndicator, isTrue);
      expect(ios.pauseLocationUpdatesAutomatically, isFalse);
      expect(ios.activityType, ActivityType.fitness);
      expect(ios.distanceFilter, 0);
    });

    test('en iOS sin segundo plano se queda solo en primer plano', () {
      final ajustes =
          UbicacionGeolocator.ajustesPara(
                const ConfiguracionRastreo(enSegundoPlano: false),
                TargetPlatform.iOS,
              )
              as AppleSettings;

      expect(ajustes.allowBackgroundLocationUpdates, isFalse);
      expect(ajustes.showBackgroundLocationIndicator, isFalse);
    });

    test('en otras plataformas usa los ajustes básicos', () {
      final ajustes = UbicacionGeolocator.ajustesPara(
        const ConfiguracionRastreo(),
        TargetPlatform.windows,
      );

      expect(ajustes.runtimeType, LocationSettings);
      expect(ajustes.distanceFilter, 0);
    });

    test('con precisión baja pide medium en todas las plataformas', () {
      const config = ConfiguracionRastreo(altaPrecision: false);

      for (final plataforma in TargetPlatform.values) {
        expect(
          UbicacionGeolocator.ajustesPara(config, plataforma).accuracy,
          LocationAccuracy.medium,
          reason: plataforma.name,
        );
      }
    });
  });

  test('ajustesBasicos no lleva nada de segundo plano', () {
    final ajustes = UbicacionGeolocator.ajustesBasicos(
      const ConfiguracionRastreo(),
    );

    expect(ajustes.runtimeType, LocationSettings);
    expect(ajustes.accuracy, LocationAccuracy.best);
    expect(ajustes.distanceFilter, 0);
  });

  group('UbicacionGeolocator.aPunto', () {
    // Así llega una lectura de Android: geolocator_android pierde las
    // banderas has* y quedan en false aunque haya medida (BUG-001).
    Position posicion({
      double accuracy = 0,
      double speed = 0,
      double speedAccuracy = 0,
      bool banderas = false,
    }) => Position(
      latitude: 6.16,
      longitude: -75.59,
      timestamp: DateTime.utc(2026, 9, 24),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: speedAccuracy,
      hasAccuracy: banderas,
      hasSpeed: banderas,
      hasSpeedAccuracy: banderas,
    );

    test(
      'conserva precisión y velocidad aunque las banderas vengan en false',
      () {
        final punto = UbicacionGeolocator.aPunto(
          posicion(accuracy: 5.1, speed: 1.4, speedAccuracy: 0.86),
        );

        expect(punto.precisionMetros, 5.1);
        expect(punto.velocidadMps, 1.4);
        expect(punto.precisionVelocidadMps, 0.86);
      },
    );

    test('una velocidad de 0 con su error medido es reposo, no falta', () {
      final punto = UbicacionGeolocator.aPunto(
        posicion(accuracy: 5.1, speedAccuracy: 0.86),
      );

      expect(punto.velocidadMps, 0);
    });

    test('lo que el sistema no midió queda en null', () {
      final punto = UbicacionGeolocator.aPunto(posicion());

      expect(punto.precisionMetros, isNull);
      expect(punto.velocidadMps, isNull);
      expect(punto.precisionVelocidadMps, isNull);
    });

    test('con las banderas en true respeta el valor aunque sea 0', () {
      final punto = UbicacionGeolocator.aPunto(posicion(banderas: true));

      expect(punto.precisionMetros, 0);
      expect(punto.velocidadMps, 0);
      expect(punto.precisionVelocidadMps, 0);
    });
  });
}
