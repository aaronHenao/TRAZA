// Los permisos y ajustes nativos que necesita la ubicación en tiempo real
// (SCRUM-129). El CI no compila Android ni iOS, así que esta es la única
// red de seguridad si un merge los tumba: sin ellos geolocator no pide
// ubicación, el servicio en primer plano no arranca o los tiles no cargan.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String manifestPrincipal;
  late String manifestDebug;
  late String infoPlist;

  setUpAll(() {
    manifestPrincipal =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    manifestDebug =
        File('android/app/src/debug/AndroidManifest.xml').readAsStringSync();
    infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
  });

  bool declaraPermiso(String manifest, String permiso) => manifest.contains(
        '<uses-permission android:name="android.permission.$permiso" />',
      );

  group('AndroidManifest.xml (main)', () {
    test('declara los permisos de ubicación', () {
      expect(declaraPermiso(manifestPrincipal, 'ACCESS_FINE_LOCATION'), isTrue);
      expect(
        declaraPermiso(manifestPrincipal, 'ACCESS_COARSE_LOCATION'),
        isTrue,
      );
    });

    test('declara lo que necesita el servicio en primer plano', () {
      expect(declaraPermiso(manifestPrincipal, 'FOREGROUND_SERVICE'), isTrue);
      expect(
        declaraPermiso(manifestPrincipal, 'FOREGROUND_SERVICE_LOCATION'),
        isTrue,
      );
      expect(declaraPermiso(manifestPrincipal, 'WAKE_LOCK'), isTrue);
      expect(declaraPermiso(manifestPrincipal, 'POST_NOTIFICATIONS'), isTrue);
    });

    test('declara INTERNET (tiles del mapa y Supabase en release)', () {
      expect(declaraPermiso(manifestPrincipal, 'INTERNET'), isTrue);
    });

    test('no pide ubicación en segundo plano (revisión especial en Play)',
        () {
      expect(
        declaraPermiso(manifestPrincipal, 'ACCESS_BACKGROUND_LOCATION'),
        isFalse,
      );
    });

    test('MainActivity sigue siendo FlutterFragmentActivity (health)', () {
      final actividad = File(
        'android/app/src/main/kotlin/com/traza/traza/MainActivity.kt',
      ).readAsStringSync();

      expect(actividad, contains('FlutterFragmentActivity'));
    });
  });

  group('AndroidManifest.xml (debug)', () {
    test('desactiva Impeller solo en debug, por el emulador', () {
      expect(
        manifestDebug,
        contains('io.flutter.embedding.android.EnableImpeller'),
      );
      expect(manifestDebug, contains('android:value="false"'));
      expect(
        manifestPrincipal,
        isNot(contains('EnableImpeller')),
        reason: 'la release debe conservar Impeller',
      );
    });
  });

  group('Info.plist', () {
    test('explica para qué usa la ubicación mientras la app está en uso',
        () {
      expect(infoPlist, contains('NSLocationWhenInUseUsageDescription'));
      final descripcion = RegExp(
        r'<key>NSLocationWhenInUseUsageDescription</key>\s*<string>([^<]+)</string>',
      ).firstMatch(infoPlist)?.group(1);
      expect(descripcion, isNotNull);
      expect(descripcion!.trim(), isNotEmpty);
    });

    test('activa el modo de ubicación en segundo plano', () {
      final modos = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(infoPlist)?.group(1);

      expect(modos, isNotNull);
      expect(modos, contains('<string>location</string>'));
    });

    test('no pide el permiso "Siempre"', () {
      expect(
        infoPlist,
        isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
      );
    });
  });
}
