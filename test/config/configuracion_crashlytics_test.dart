// Ajustes nativos de Firebase Crashlytics y privacidad de los reportes
// (Crashlytics). Igual que configuracion_nativa_test.dart: el CI no compila
// Android, así que si un merge tumba los plugins de Gradle o
// google-services.json, Crashlytics deja de recibir errores sin que nadie lo
// note; y si alguien identifica al usuario, sus datos salen del teléfono.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('android/app/build.gradle.kts', () {
    late List<String> lineas;

    setUpAll(() {
      lineas = File(
        'android/app/build.gradle.kts',
      ).readAsLinesSync().map((linea) => linea.trim()).toList();
    });

    /// Compara la línea completa: así no cuenta si quedó comentada con `//`
    /// o declarada con `apply false`.
    bool aplicaPlugin(String id) => lineas.contains('id("$id")');

    test('aplica el plugin de Google Services (lee google-services.json)', () {
      expect(aplicaPlugin('com.google.gms.google-services'), isTrue);
    });

    test('aplica el plugin de Crashlytics', () {
      expect(aplicaPlugin('com.google.firebase.crashlytics'), isTrue);
    });
  });

  group('android/app/google-services.json', () {
    final archivo = File('android/app/google-services.json');

    test('existe', () {
      // Sin él, el plugin de Google Services rompe la compilación.
      expect(archivo.existsSync(), isTrue);
    });

    test('declara el paquete com.traza.traza', () {
      // Si no coincide con el applicationId, Firebase no reconoce la app.
      expect(
        archivo.readAsStringSync(),
        matches(RegExp(r'"package_name"\s*:\s*"com\.traza\.traza"')),
      );
    });
  });

  group('privacidad de los reportes', () {
    /// APIs del plugin que identifican al usuario (setUserIdentifier,
    /// setCustomKey, log) o que envían la descripción de widgets con
    /// FlutterErrorDetails completo (recordFlutterError y
    /// recordFlutterFatalError).
    const apisProhibidas = [
      'setUserIdentifier',
      'setCustomKey',
      'recordFlutterError',
      'recordFlutterFatalError',
      'FirebaseCrashlytics.instance.log',
    ];

    test('ningún archivo de lib/ identifica al usuario ante Crashlytics', () {
      final archivosDart = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((archivo) => archivo.path.endsWith('.dart'))
          .toList();
      // Si no encontrara lib/, la prueba pasaría sin revisar nada.
      expect(archivosDart, isNotEmpty);

      final hallazgos = [
        for (final archivo in archivosDart)
          for (final api in apisProhibidas)
            if (archivo.readAsStringSync().contains(api))
              '${archivo.path}: $api',
      ];

      expect(hallazgos, isEmpty);
    });
  });
}
