import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recorrido.dart';
import '../models/resumen_entrenamiento.dart';
import 'actividad_provider.dart';
import 'entrenamiento_actual_provider.dart';
import 'entrenamiento_service.dart';
import 'objetivos_service.dart' show SesionRequeridaException;
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

/// Inicio del entrenamiento (SCRUM-99).
final inicioEntrenamientoProvider = Provider<InicioEntrenamiento>(
  InicioEntrenamiento.new,
);

/// Crea el entrenamiento cuando el usuario toca "Iniciar actividad".
///
/// Es el otro extremo de [CierreEntrenamiento]: aquí nace la fila de
/// `entrenamientos` con la actividad elegida en los chips (SCRUM-93), y su id
/// queda en [entrenamientoActualProvider] para que los puntos GPS que se
/// registren (SCRUM-110) tengan dueño.
class InicioEntrenamiento {
  const InicioEntrenamiento(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para empezar a entrenar.';
  static const noSePudo =
      'No se pudo iniciar el entrenamiento. Inténtalo de nuevo.';

  /// Devuelve null si el entrenamiento quedó creado y la actividad puede
  /// arrancar, o el mensaje para el usuario si no se pudo (SCRUM-100). En ese
  /// caso no queda nada a medias: sin id, no hay entrenamiento en curso.
  Future<String?> iniciar() async {
    // Sin configuración no hay tipo de actividad con id, y `tipo_actividad_id`
    // es obligatorio (ver ConfiguracionInicio.para).
    final configuracion = _ref.read(configuracionInicioProvider);
    if (configuracion == null) return sinSesion;

    try {
      final entrenamientoId = await _ref
          .read(entrenamientoRepositoryProvider)
          .crear(tipoActividadId: configuracion.tipoActividadId);
      _ref.read(entrenamientoEnCursoProvider.notifier).fijar(entrenamientoId);
      return null;
    } on SesionRequeridaException {
      return sinSesion;
    } catch (error) {
      debugPrint('No se pudo crear el entrenamiento: $error');
      return noSePudo;
    }
  }
}

/// Descarte del entrenamiento en curso (SCRUM-96).
final descarteEntrenamientoProvider = Provider<DescarteEntrenamiento>(
  DescarteEntrenamiento.new,
);

/// Descarta el entrenamiento cuando el usuario elige no guardarlo.
///
/// Deja la fila `cancelado` y libera la actividad, para que el usuario pueda
/// elegir otra y empezar de nuevo.
class DescarteEntrenamiento {
  const DescarteEntrenamiento(this._ref);

  final Ref _ref;

  Future<void> descartar() async {
    final entrenamientoId = _ref.read(entrenamientoActualProvider);

    // Se suelta primero lo de la app: el usuario ya decidió descartar y la
    // pantalla no debe quedarse esperando a la red.
    _ref.read(actividadIniciadaProvider.notifier).marcarTerminada();
    _ref.read(entrenamientoEnCursoProvider.notifier).limpiar();

    if (entrenamientoId == null) return;
    try {
      await _ref
          .read(entrenamientoRepositoryProvider)
          .cancelar(
            entrenamientoId: entrenamientoId,
            fechaFin: _ref.read(relojProvider)(),
          );
    } catch (error) {
      // No se le avisa: el entrenamiento se descartó igual y no hay nada que
      // el usuario pueda hacer. La fila queda `en_curso` en la base.
      debugPrint('No se pudo marcar el entrenamiento como cancelado: $error');
    }
  }
}

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
    // Ya no hay entrenamiento en curso: el siguiente empieza con el suyo
    // (SCRUM-96).
    _ref.read(entrenamientoEnCursoProvider.notifier).limpiar();
    return null;
  }
}
