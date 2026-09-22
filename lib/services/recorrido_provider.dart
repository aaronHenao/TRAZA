import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/punto_gps.dart';
import '../models/recorrido.dart';
import 'calculadora_distancia.dart';
import 'cronometro_provider.dart';
import 'entrenamiento_actual_provider.dart';
import 'puntos_gps_service.dart';
import 'ubicacion_provider.dart';

// El `id` del entrenamiento dueño de los puntos lo fija el flujo de inicio
// (SCRUM-99). Se re-exporta para que quien registre puntos no tenga que
// saber de dónde sale.
export 'entrenamiento_actual_provider.dart' show entrenamientoActualProvider;

/// Persistencia real. Las pruebas la sobrescriben.
final repositorioPuntosGpsProvider = Provider<RepositorioPuntosGps>(
  (ref) => RepositorioPuntosGpsSupabase(Supabase.instance.client),
);

/// Recorrido de la actividad en curso (SCRUM-110): cada lectura aceptada
/// de [posicionEnVivoProvider] se registra en local; al finalizar,
/// [RecorridoNotifier.sincronizar] envía todo el lote a `puntos_gps`.
///
/// Solo registra y expone. Dibujar el trazo y calcular la distancia son
/// de otras HU: leen `puntos` de aquí. Vive mientras la pantalla de
/// entrenamiento lo observe.
final recorridoProvider =
    NotifierProvider.autoDispose<RecorridoNotifier, Recorrido>(
  RecorridoNotifier.new,
);

class RecorridoNotifier extends AutoDisposeNotifier<Recorrido> {
  bool _activo = true;

  @override
  Recorrido build() {
    _activo = true;
    ref.onDispose(() => _activo = false);

    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      final punto = siguiente.valueOrNull;
      if (punto != null) _registrar(punto);
    });

    return const Recorrido();
  }

  /// Registra la lectura en local. No toca la red.
  void _registrar(PuntoGps punto) {
    // En pausa manual (o ya finalizado) el usuario no está haciendo la
    // ruta: la lectura no cuenta, igual que en el prototipo. En una
    // auto-pausa sí se registra: el usuario no pidió parar, solo se quedó
    // quieto, y hace falta seguir escuchando para saber cuándo arranca de
    // nuevo (SCRUM-116).
    if (!ref.read(cronometroProvider).registraRecorrido) return;

    // El sistema entrega todas las lecturas; el filtro de ruido es este.
    // Descarta el jitter del GPS con el usuario quieto y, de paso, la
    // lectura puntual inicial repetida en el primer evento del stream.
    final ultimo = state.ultimo;
    if (ultimo != null) {
      final avance = CalculadoraDistancia.haversineMetros(
        ultimo.latitud,
        ultimo.longitud,
        punto.latitud,
        punto.longitud,
      );
      final minimo = ref
          .read(configuracionRastreoProvider)
          .distanciaMinimaRegistroMetros;
      if (avance < minimo) return;
    }

    state = state.copyWith(puntos: [...state.puntos, punto]);
  }

  /// Envía todos los puntos a `puntos_gps` en una sola operación.
  ///
  /// Se llama al finalizar la actividad. Devuelve `true` si el lote
  /// quedó guardado (o no había nada que guardar). Si falla, los puntos
  /// siguen en local y se puede volver a llamar.
  Future<bool> sincronizar() async {
    final entrenamientoId = ref.read(entrenamientoActualProvider);
    final puntos = state.puntos;

    if (entrenamientoId == null || puntos.isEmpty) {
      _actualizar(EstadoSincronizacion.completada);
      return true;
    }

    final repositorio = ref.read(repositorioPuntosGpsProvider);
    _actualizar(EstadoSincronizacion.enCurso);
    try {
      await repositorio.guardarTodos(
        entrenamientoId: entrenamientoId,
        puntos: puntos,
      );
      _actualizar(EstadoSincronizacion.completada);
      return true;
    } catch (error) {
      debugPrint('No se pudo sincronizar el recorrido: $error');
      _actualizar(EstadoSincronizacion.fallida);
      return false;
    }
  }

  void _actualizar(EstadoSincronizacion sincronizacion) {
    if (_activo) state = state.copyWith(sincronizacion: sincronizacion);
  }
}
