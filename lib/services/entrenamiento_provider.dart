import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recorrido.dart';
import '../models/resumen_entrenamiento.dart';
import 'actividad_provider.dart';
import 'entrenamiento_service.dart';
import 'recorrido_provider.dart';
import 'reloj_provider.dart';

/// Datos de un entrenamiento finalizado, leídos de Supabase por su id
/// (SCRUM-118).
///
/// `autoDispose`: al salir del resumen se descartan, así que nunca se
/// reutilizan los de una sesión anterior.
final entrenamientoFinalizadoProvider = FutureProvider.autoDispose
    .family<ResumenEntrenamiento?, String>(
      (ref, entrenamientoId) => ref
          .watch(entrenamientoRepositoryProvider)
          .cargarFinalizado(entrenamientoId),
    );

/// Cierre del entrenamiento en curso (SCRUM-121).
final cierreEntrenamientoProvider = Provider<CierreEntrenamiento>(
  CierreEntrenamiento.new,
);

/// Cierra el entrenamiento cuando el usuario toca "Finalizar".
///
/// Corre después de que la pantalla del entrenamiento (de Aaron) detiene el
/// cronómetro y envía los puntos a `puntos_gps` (SCRUM-110). Actualiza la fila
/// de `entrenamientos` con `fecha_fin`, `duracion_segundos`,
/// `distancia_total_m` y `estado = 'finalizado'`, y libera la actividad
/// elegida (SCRUM-94).
class CierreEntrenamiento {
  const CierreEntrenamiento(this._ref);

  final Ref _ref;

  /// Devuelve null si el entrenamiento quedó cerrado y se puede pasar al
  /// resumen, o el mensaje para el usuario si algo no se guardó. En ese caso
  /// la actividad sigue en pantalla y "Finalizar" se puede volver a tocar.
  Future<String?> finalizar({
    required Duration duracion,
    required Recorrido recorrido,
  }) async {
    // Sin los puntos guardados el resumen no tendría recorrido, así que el
    // entrenamiento no se da por finalizado.
    if (recorrido.sincronizacion == EstadoSincronizacion.fallida) {
      return 'No se pudo guardar el recorrido. Inténtalo de nuevo.';
    }

    // Sin entrenamiento creado (todavía no hay login ni SCRUM-99) no hay fila
    // que actualizar: se pasa directo al resumen.
    final entrenamientoId = _ref.read(entrenamientoActualProvider);
    if (entrenamientoId != null) {
      try {
        await _ref
            .read(entrenamientoRepositoryProvider)
            .finalizar(
              entrenamientoId: entrenamientoId,
              fechaFin: _ref.read(relojProvider)(),
              duracion: duracion,
              // La distancia la calculan y exponen SCRUM-111 y SCRUM-112;
              // mientras no existan, `distancia_total_m` queda vacía.
            );
      } catch (error) {
        debugPrint('No se pudo cerrar el entrenamiento: $error');
        return 'No se pudo guardar el entrenamiento. Inténtalo de nuevo.';
      }
    }

    _ref.read(actividadIniciadaProvider.notifier).marcarTerminada();
    return null;
  }
}
