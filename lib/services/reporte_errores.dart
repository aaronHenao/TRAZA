import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Envía un error al destino de los reportes: Crashlytics en la app, una
/// función que los anota en las pruebas.
typedef ReportarError =
    void Function(Object error, StackTrace pila, {required bool fatal});

/// Conecta la app con Firebase y manda a Crashlytics los errores que nadie
/// atrapó (Crashlytics).
///
/// Solo en Android, que es la única plataforma configurada
/// (`flutterfire configure --platforms=android`): en las demás,
/// `DefaultFirebaseOptions` lanza un error y la app no abriría.
///
/// Solo en release: en debug los errores son de quien está programando y ya
/// los ve en consola. Apagar la recolección también frena los crashes
/// nativos (Java/Kotlin), que Crashlytics captura por su cuenta.
///
/// Si Firebase falla, la app abre igual: el reporte de errores es un
/// diagnóstico, no algo de lo que dependa el corredor.
Future<void> iniciarReporteErrores() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
    if (!kReleaseMode) return;

    // `ignore`: si el envío falla, ese error no puede volver a entrar por
    // PlatformDispatcher.onError, que lo mandaría otra vez sin fin.
    capturarErrores(
      (error, pila, {required fatal}) =>
          crashlytics.recordError(error, pila, fatal: fatal).ignore(),
    );
  } catch (error) {
    debugPrint('Crashlytics no inició: ${error.runtimeType}');
    return;
  }

  if (_eventoDePrueba) {
    // Error sin atrapar con un correo inventado en el mensaje. En la consola
    // de Firebase debe llegar solo "StateError": es la evidencia de que los
    // datos personales no salen del teléfono.
    unawaited(
      Future<void>(
        () => throw StateError('Prueba de Crashlytics para prueba@traza.co'),
      ),
    );
  }
}

/// Se activa al compilar con `--dart-define=CRASHLYTICS_PRUEBA=true`.
const _eventoDePrueba = bool.fromEnvironment('CRASHLYTICS_PRUEBA');

/// Hace que todo error no atrapado llegue a [reportar] sin datos personales.
///
/// Solo viaja el tipo del error (`StateError`, `PostgrestException`) y su
/// pila. El mensaje no: el de Supabase puede traer el valor que chocó y el
/// del GPS, coordenadas. Tampoco la descripción de widgets de los errores de
/// Flutter, que puede incluir el texto en pantalla. Mandar solo lo que se
/// sabe seguro es más confiable que intentar borrar lo personal.
void capturarErrores(ReportarError reportar) {
  // Errores al construir o pintar widgets.
  FlutterError.onError = (detalles) {
    // Se sigue mostrando en consola, como antes de Crashlytics.
    FlutterError.presentError(detalles);
    reportar(
      _soloElTipo(detalles.exception),
      detalles.stack ?? StackTrace.empty,
      fatal: true,
    );
  };
  // Errores asíncronos: un Future que falla sin que nadie lo espere.
  PlatformDispatcher.instance.onError = (error, pila) {
    reportar(_soloElTipo(error), pila, fatal: true);
    return true;
  };
}

String _soloElTipo(Object error) => error.runtimeType.toString();
