import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estado_cronometro.dart';
import '../models/punto_gps.dart';
import '../models/recorrido.dart';
import 'calculadora_distancia.dart';
import 'criterio_movimiento.dart';
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

  /// La siguiente lectura registrada empieza un tramo nuevo: se acaba de
  /// reanudar tras una pausa.
  bool _tramoNuevo = false;

  @override
  Recorrido build() {
    _activo = true;
    ref.onDispose(() => _activo = false);

    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      final punto = siguiente.valueOrNull;
      if (punto != null) _registrar(punto);
    });

    ref.listen(cronometroProvider.select((estado) => estado.marcha), (
      anterior,
      actual,
    ) {
      if (anterior == MarchaCronometro.pausado &&
          actual == MarchaCronometro.enCurso) {
        _tramoNuevo = true;
      }
    });

    return const Recorrido();
  }

  /// Registra la lectura en local. No toca la red.
  void _registrar(PuntoGps punto) {
    // En pausa (o ya finalizado) el usuario no está haciendo la ruta:
    // la lectura no cuenta, igual que en el prototipo.
    if (!ref.read(cronometroProvider).estaEnCurso) return;
    if (_tramoNuevo && state.puntos.isNotEmpty) {
      // Lo que el usuario se movió en pausa no es parte de la ruta: la
      // primera lectura tras reanudar no se compara con el último punto de
      // antes, sino que abre un tramo nuevo (BUG-005).
      _tramoNuevo = false;
      state = state.copyWith(
        puntos: [...state.puntos, punto],
        cortes: [...state.cortes, state.puntos.length],
      );
      return;
    }
    if (!_esAvance(punto)) return;
    state = state.copyWith(puntos: [...state.puntos, punto]);
  }

  /// `true` si [punto] alarga el trazo.
  ///
  /// El sistema entrega todas las lecturas (una por segundo), así que el
  /// filtro de ruido es este (SCRUM-116): con el usuario quieto el GPS
  /// "baila" hasta decenas de metros y el trazo acumularía zigzags
  /// fantasma. Hace falta separarse `distanciaMinimaRegistroMetros`
  /// del último punto y, además, que haya movimiento: según la velocidad
  /// Doppler si es fiable, o si no, un desplazamiento mayor que el error
  /// de las lecturas.
  bool _esAvance(PuntoGps punto) {
    final ultimo = state.ultimo;
    if (ultimo == null) return true;

    final avance = CalculadoraDistancia.haversineMetros(
      ultimo.latitud,
      ultimo.longitud,
      punto.latitud,
      punto.longitud,
    );
    final minimo = ref
        .read(configuracionRastreoProvider)
        .distanciaMinimaRegistroMetros;
    if (avance < minimo) return false;

    const criterio = CriterioMovimiento();
    final velocidad = criterio.velocidadFiable(punto);
    if (velocidad != null) return criterio.esMovimiento(velocidad);

    // Sin velocidad fiable basta con salir del radio de error. Es más
    // permisivo que el umbral de la distancia (2.5 × el error): un zigzag
    // en el trazo apenas se nota, pero un marcador que no avanza sí. Los
    // kilómetros no salen de aquí, así que no se inflan.
    final ruido = math.max(
      ultimo.precisionMetros ?? 0,
      punto.precisionMetros ?? 0,
    );
    return avance >= ruido;
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
