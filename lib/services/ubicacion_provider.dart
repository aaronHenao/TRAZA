import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/punto_gps.dart';
import 'reloj_provider.dart';
import 'ubicacion_service.dart';

/// Fuente real de posiciones. Las pruebas la sobrescriben.
final fuenteUbicacionProvider =
    Provider<FuenteUbicacion>((ref) => const UbicacionGeolocator());

/// Frecuencia y calidad del rastreo (SCRUM-110).
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
  final reloj = ref.watch(relojProvider);

  final controlador = StreamController<PuntoGps>();
  // Las lecturas imprecisas o viejas se descartan antes de llegar a la
  // pantalla o al registro: ni el mapa salta ni se guarda un punto malo.
  final suscripcion = fuente
      .posiciones(configuracion)
      .where((punto) => configuracion.acepta(punto, ahora: reloj()))
      .listen(
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
