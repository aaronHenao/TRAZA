import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:traza/services/ubicacion_service.dart';

void main() {
  group('UbicacionGeolocator.ajustesPara', () {
    test('en Android levanta el servicio en primer plano con notificación',
        () {
      final ajustes = UbicacionGeolocator.ajustesPara(
        const ConfiguracionRastreo(),
        TargetPlatform.android,
      );

      expect(ajustes, isA<AndroidSettings>());
      final android = ajustes as AndroidSettings;
      expect(android.accuracy, LocationAccuracy.best);
      expect(android.distanceFilter, 0);

      final notificacion = android.foregroundNotificationConfig!;
      expect(notificacion.notificationTitle, tituloNotificacionRastreo);
      expect(notificacion.notificationText, textoNotificacionRastreo);
      expect(notificacion.setOngoing, isTrue);
      expect(notificacion.enableWakeLock, isTrue);
    });

    test('en Android sin segundo plano no hay servicio ni notificación', () {
      final ajustes = UbicacionGeolocator.ajustesPara(
        const ConfiguracionRastreo(enSegundoPlano: false),
        TargetPlatform.android,
      ) as AndroidSettings;

      expect(ajustes.foregroundNotificationConfig, isNull);
    });

    test('en iOS permite seguir en segundo plano como actividad física',
        () {
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
      final ajustes = UbicacionGeolocator.ajustesPara(
        const ConfiguracionRastreo(enSegundoPlano: false),
        TargetPlatform.iOS,
      ) as AppleSettings;

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
}
