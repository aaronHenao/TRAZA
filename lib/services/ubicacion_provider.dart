import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_permisos.dart';
import '../models/punto_gps.dart';
import 'permisos_provider.dart';
import 'reloj_provider.dart';
import 'ubicacion_service.dart';

/// Fuente real de posiciones. Las pruebas la sobrescriben.
final fuenteUbicacionProvider = Provider<FuenteUbicacion>(
  (ref) => const UbicacionGeolocator(),
);

/// Frecuencia y calidad del rastreo (SCRUM-110).
final configuracionRastreoProvider = Provider<ConfiguracionRastreo>(
  (ref) => const ConfiguracionRastreo(),
);

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

/// Dónde está el usuario, o por qué no se sabe (SCRUM-245).
///
/// Es un tipo cerrado para que quien lo use tenga que contemplar los cuatro
/// casos: cada uno se le cuenta distinto al usuario —no es lo mismo no
/// haber dado el permiso que tener el GPS apagado—, y un `null` a secas
/// obligaría a adivinar cuál de ellos pasó.
sealed class UbicacionUsuario {
  const UbicacionUsuario();
}

/// Se sabe dónde está.
class UbicacionConocida extends UbicacionUsuario {
  const UbicacionConocida(this.punto);

  final PuntoGps punto;
}

/// El usuario no ha concedido el permiso de ubicación. No se le pregunta
/// nada al GPS: pedirlo es de la pantalla, que es quien puede explicarle
/// para qué sirve (SCRUM-82 y SCRUM-290).
class UbicacionSinPermiso extends UbicacionUsuario {
  const UbicacionSinPermiso();
}

/// Hay permiso, pero la ubicación del teléfono está apagada. El usuario la
/// enciende desde los ajustes del sistema, no desde la app.
class UbicacionApagada extends UbicacionUsuario {
  const UbicacionApagada();
}

/// El GPS no respondió a tiempo o el plugin falló. Pasa bajo techo, y lo
/// que toca es reintentar.
class UbicacionNoSePudo extends UbicacionUsuario {
  const UbicacionNoSePudo();
}

/// Cuánto se espera una lectura antes de rendirse.
///
/// Diez segundos: bajo techo el primer fix puede tardar mucho más, y una
/// lista de rutas no puede quedarse en blanco esperándolo.
const tiempoMaximoUbicacion = Duration(seconds: 10);

/// La ubicación del dispositivo ahora mismo, para el resto de la app
/// (SCRUM-245).
///
/// No pide permisos ni los gestiona: lee los que ya maneja
/// [permisosProvider] (SCRUM-37) y, si no están concedidos, ni toca el GPS.
/// Cuando el usuario los concede desde la pantalla, este provider se entera
/// solo —observa ese estado— y vuelve a leer.
///
/// Mientras la consulta de permisos del arranque no haya terminado, el
/// estado es `desconocido` y esto responde [UbicacionSinPermiso]. Las
/// pantallas esperan a `EstadoPermisos.consultado` antes de pintar nada,
/// así que ese instante no se ve.
///
/// `autoDispose`: la ubicación de hace media hora no sirve para decir qué
/// hay cerca, así que se vuelve a leer cada vez que alguien la necesita.
final ubicacionActualProvider = FutureProvider.autoDispose<UbicacionUsuario>((
  ref,
) async {
  final permiso = ref.watch(permisosProvider.select((e) => e.ubicacion));
  if (permiso != EstadoPermiso.concedido) return const UbicacionSinPermiso();

  final fuente = ref.watch(fuenteUbicacionProvider);
  // El permiso no basta: se puede tener y estar la ubicación del teléfono
  // apagada, y entonces no hay GPS al que preguntarle.
  if (!await fuente.servicioActivo()) return const UbicacionApagada();

  try {
    return UbicacionConocida(
      await fuente.ubicacionActual(tiempoMaximo: tiempoMaximoUbicacion),
    );
  } catch (error) {
    // Un fallo del GPS no es un error de la app: la pantalla lo cuenta y
    // ofrece reintentar, en vez de romperse.
    debugPrint('No se pudo leer la ubicación: $error');
    return const UbicacionNoSePudo();
  }
});
