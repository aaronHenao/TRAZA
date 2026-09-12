import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/punto_gps.dart';
import 'ubicacion_service.dart';

/// Fuente real de posiciones. Las pruebas la sobrescriben.
final fuenteUbicacionProvider =
    Provider<FuenteUbicacion>((ref) => const UbicacionGeolocator());

/// Parámetros del rastreo. SCRUM-110 define los valores definitivos.
final configuracionRastreoProvider =
    Provider<ConfiguracionRastreo>((ref) => const ConfiguracionRastreo());

/// Posición del usuario en vivo mientras la actividad está en curso
/// (SCRUM-108).
///
/// El stream se abre cuando la pantalla de entrenamiento lo observa y se
/// cierra solo cuando deja de hacerlo; así la captura dura exactamente
/// lo que dura la actividad en pantalla.
///
/// No basta con devolver `fuente.posiciones(...)` directamente: Riverpod
/// mantiene un oyente interno hasta que el stream emite su primer valor,
/// así que si el usuario saliera de la pantalla antes del primer fix del
/// GPS, el GPS se quedaría encendido hasta recibirlo. Por eso la
/// suscripción a la fuente se cancela explícitamente en `onDispose`.
final posicionEnVivoProvider = StreamProvider.autoDispose<PuntoGps>((ref) {
  final fuente = ref.watch(fuenteUbicacionProvider);
  final configuracion = ref.watch(configuracionRastreoProvider);

  final controlador = StreamController<PuntoGps>();
  final suscripcion = fuente.posiciones(configuracion).listen(
        controlador.add,
        onError: controlador.addError,
        onDone: controlador.close,
      );

  ref.onDispose(() async {
    await suscripcion.cancel();
    await controlador.close();
  });

  return controlador.stream;
});
