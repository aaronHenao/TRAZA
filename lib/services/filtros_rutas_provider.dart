import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dificultad.dart';
import '../models/filtros_rutas.dart';
import '../models/rango_distancia.dart';
import 'preferencias_explorar.dart';

/// El rango de distancia elegido en Explorar rutas, o null si no hay
/// ninguno (SCRUM-273).
///
/// Uno a la vez: elegir otro reemplaza al anterior, y tocar el elegido lo
/// quita. Vale para las cercanas y para los resultados de una búsqueda.
/// Se recuerda en el teléfono: al volver a Explorar, o al abrir la app,
/// sigue elegido (preferencias de Explorar, Desarrollo Móvil).
final rangoDistanciaProvider =
    NotifierProvider.autoDispose<RangoDistanciaNotifier, RangoDistancia?>(
      RangoDistanciaNotifier.new,
    );

class RangoDistanciaNotifier extends AutoDisposeNotifier<RangoDistancia?> {
  @override
  RangoDistancia? build() {
    final preferencias = ref.watch(preferenciasExplorarProvider);
    listenSelf((_, elegido) {
      // Al crearse vale lo guardado: no hace falta volver a escribirlo.
      if (elegido == preferencias.distancia()) return;
      unawaited(_guardar(() => preferencias.guardarDistancia(elegido)));
    });
    return preferencias.distancia();
  }

  /// Null quita el filtro.
  void elegir(RangoDistancia? rango) => state = rango;
}

/// La dificultad elegida en Explorar rutas, o null para verlas todas
/// (HU-36).
///
/// La eligen los chips de la fila de dificultades (SCRUM-267), y se combina
/// con la distancia (SCRUM-275). Mientras las rutas no tengan dificultad
/// (SCRUM-363), ninguna pasa este filtro. Se recuerda en el teléfono, como
/// el rango.
final dificultadRutasProvider =
    NotifierProvider.autoDispose<DificultadRutasNotifier, Dificultad?>(
      DificultadRutasNotifier.new,
    );

class DificultadRutasNotifier extends AutoDisposeNotifier<Dificultad?> {
  @override
  Dificultad? build() {
    final preferencias = ref.watch(preferenciasExplorarProvider);
    listenSelf((_, elegida) {
      if (elegida == preferencias.dificultad()) return;
      unawaited(_guardar(() => preferencias.guardarDificultad(elegida)));
    });
    return preferencias.dificultad();
  }

  /// Null las muestra todas.
  void elegir(Dificultad? dificultad) => state = dificultad;
}

/// Si el teléfono no deja guardar, el filtro se aplica igual: lo único que
/// se pierde es recordarlo la próxima vez.
Future<void> _guardar(Future<void> Function() guardar) async {
  try {
    await guardar();
  } catch (error) {
    debugPrint('No se pudo recordar el filtro de Explorar: $error');
  }
}

/// Todo lo elegido para filtrar, junto: lo que aplica la lista (SCRUM-275).
final filtrosRutasProvider = Provider.autoDispose<FiltrosRutas>(
  (ref) => FiltrosRutas(
    dificultad: ref.watch(dificultadRutasProvider),
    distancia: ref.watch(rangoDistanciaProvider),
  ),
);
