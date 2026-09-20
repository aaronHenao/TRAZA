// Ajustes nativos para leer datos de salud (SCRUM-78). Igual que
// configuracion_nativa_test.dart: el CI no compila Android ni iOS, y sin estas
// líneas Health Connect o Apple Health rechazan el permiso sin avisar.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:traza/services/permisos_service.dart';

void main() {
  late String manifest;
  late String infoPlist;

  setUpAll(() {
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
  });

  group('AndroidManifest.xml', () {
    /// Permiso de Health Connect que corresponde a cada tipo que se lee.
    const permisoDe = {
      HealthDataType.HEART_RATE: 'READ_HEART_RATE',
      HealthDataType.ACTIVE_ENERGY_BURNED: 'READ_ACTIVE_CALORIES_BURNED',
      HealthDataType.STEPS: 'READ_STEPS',
    };

    test('declara la lectura de cada dato de salud que usa la app', () {
      for (final tipo in tiposDatosSalud) {
        final permiso = permisoDe[tipo];
        expect(permiso, isNotNull, reason: 'falta mapear $tipo en la prueba');
        expect(
          manifest,
          contains('android.permission.health.$permiso'),
          reason: '$tipo',
        );
      }
    });

    test('no pide escribir datos de salud', () {
      expect(manifest, isNot(contains('android.permission.health.WRITE_')));
    });

    test('puede saber si Health Connect está instalado', () {
      expect(manifest, contains('com.google.android.apps.healthdata'));
    });

    test('explica el uso de los datos en Android 14+', () {
      expect(manifest, contains('android.intent.action.VIEW_PERMISSION_USAGE'));
      expect(manifest, contains('android.intent.category.HEALTH_PERMISSIONS'));
    });
  });

  group('Info.plist', () {
    test('explica para qué lee los datos de salud', () {
      for (final clave in [
        'NSHealthShareUsageDescription',
        'NSHealthUpdateUsageDescription',
      ]) {
        final descripcion = RegExp(
          '<key>$clave</key>\\s*<string>([^<]+)</string>',
        ).firstMatch(infoPlist)?.group(1);
        expect(descripcion?.trim(), isNotEmpty, reason: clave);
      }
    });
  });
}
