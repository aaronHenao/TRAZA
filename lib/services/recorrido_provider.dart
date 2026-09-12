import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/punto_gps.dart';
import '../models/recorrido.dart';
import 'cronometro_provider.dart';
import 'puntos_gps_service.dart';
import 'ubicacion_provider.dart';

/// `id` del entrenamiento en curso, dueño de los puntos que se registran.
///
/// Crear el entrenamiento en Supabase es de SCRUM-45; esta HU lo asume
/// existente. Mientras nadie lo provea, vale `null` y el recorrido se
/// queda en local sin sincronizar.
final entrenamientoActualProvider = Provider<String?>((ref) => null);

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
    // En pausa (o ya finalizado) el usuario no está haciendo la ruta:
    // la lectura no cuenta, igual que en el prototipo.
    if (!ref.read(cronometroProvider).estaEnCurso) return;
    // La lectura puntual inicial y el primer evento del stream suelen ser
    // el mismo punto: no vale la pena guardarlo dos veces.
    if (punto.mismaCoordenadaQue(state.ultimo)) return;

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
