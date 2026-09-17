import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recorrido.dart';
import '../models/resumen_entrenamiento.dart';
import 'actividad_provider.dart';
import 'entrenamiento_actual_provider.dart';
import 'entrenamiento_service.dart';
import 'objetivos_service.dart' show SesionRequeridaException;
import 'ubicacion_provider.dart';
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
  static const ubicacionApagada =
      'Activa la ubicación del teléfono para empezar a entrenar.';

  /// Devuelve null si el entrenamiento quedó creado y la actividad puede
  /// arrancar, o el mensaje para el usuario si no se pudo (SCRUM-100). En ese
  /// caso no queda nada a medias: sin id, no hay entrenamiento en curso.
  Future<String?> iniciar() async {
    // Sin configuración no hay tipo de actividad con id, y `tipo_actividad_id`
    // es obligatorio (ver ConfiguracionInicio.para).
    final configuracion = _ref.read(configuracionInicioProvider);
    if (configuracion == null) return sinSesion;

    // Si algún descarte anterior no se pudo cerrar, este es buen momento:
    // el usuario está empezando otro, así que lo más probable es que haya
    // red. Sin esperar, para no retrasar el arranque.
    unawaited(_ref.read(descarteEntrenamientoProvider).reintentarPendientes());

    try {
      // Con el permiso concedido pero la ubicación del teléfono apagada no
      // llegaría ni una lectura: el entrenamiento se quedaría vacío y
      // abierto, buscando una señal que nunca va a existir.
      if (!await _ref.read(fuenteUbicacionProvider).servicioActivo()) {
        return ubicacionApagada;
      }

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

/// Un entrenamiento que el usuario descartó pero que todavía no se pudo
/// cerrar en la base.
///
/// [fechaFin] es de cuándo lo descartó, no de cuándo se logró guardar.
typedef DescartePendiente = ({String entrenamientoId, DateTime fechaFin});

/// Descartes que quedaron sin cerrar, a la espera de otro intento.
///
/// Solo mientras la app esté abierta: si se cierra antes de conseguirlo, esas
/// filas se quedan `en_curso` y hay que limpiarlas desde el dashboard.
class DescartesPendientesNotifier extends Notifier<List<DescartePendiente>> {
  @override
  List<DescartePendiente> build() => const [];

  void agregar(DescartePendiente descarte) {
    if (state.any((p) => p.entrenamientoId == descarte.entrenamientoId)) return;
    state = [...state, descarte];
  }

  void quitar(String entrenamientoId) => state = state
      .where((pendiente) => pendiente.entrenamientoId != entrenamientoId)
      .toList();
}

final descartesPendientesProvider =
    NotifierProvider<DescartesPendientesNotifier, List<DescartePendiente>>(
      DescartesPendientesNotifier.new,
    );

/// Cuánto se espera antes de reintentar un descarte. Las pruebas lo ponen en
/// cero para no esperar de verdad.
final esperaEntreIntentosProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

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

  /// Intentos seguidos antes de dejarlo para después. Un corte de red de unos
  /// segundos —lo que más pasa— se resuelve aquí.
  static const intentos = 3;


  Future<void> descartar() async {
    final entrenamientoId = _ref.read(entrenamientoActualProvider);

    // Se suelta primero lo de la app: el usuario ya decidió descartar y la
    // pantalla no debe quedarse esperando a la red.
    _ref.read(actividadIniciadaProvider.notifier).marcarTerminada();
    _ref.read(entrenamientoEnCursoProvider.notifier).limpiar();

    if (entrenamientoId == null) return;
    await _cerrar((
      entrenamientoId: entrenamientoId,
      fechaFin: _ref.read(relojProvider)(),
    ));
  }

  /// Vuelve a intentar los descartes que quedaron sin cerrar.
  ///
  /// La llama el inicio del siguiente entrenamiento: si el usuario está
  /// empezando otro, lo más probable es que ya haya red.
  Future<void> reintentarPendientes() async {
    for (final pendiente in [..._ref.read(descartesPendientesProvider)]) {
      await _cerrar(pendiente, intentos: 1);
    }
  }

  /// Marca la fila como cancelada, reintentando si la red falla. Si aun así
  /// no lo consigue, la anota para el próximo intento.
  Future<void> _cerrar(
    DescartePendiente descarte, {
    int intentos = DescarteEntrenamiento.intentos,
  }) async {
    final pendientes = _ref.read(descartesPendientesProvider.notifier);

    for (var intento = 1; intento <= intentos; intento++) {
      try {
        await _ref
            .read(entrenamientoRepositoryProvider)
            .cancelar(
              entrenamientoId: descarte.entrenamientoId,
              fechaFin: descarte.fechaFin,
            );
        pendientes.quitar(descarte.entrenamientoId);
        return;
      } on EntrenamientoNoEncontradoException {
        // Ya no estaba en curso: alguien lo cerró antes. No hay nada que
        // reintentar.
        pendientes.quitar(descarte.entrenamientoId);
        return;
      } catch (error) {
        debugPrint(
          'Intento $intento de descartar ${descarte.entrenamientoId}: $error',
        );
        if (intento < intentos) {
          await Future.delayed(
            _ref.read(esperaEntreIntentosProvider) * intento,
          );
        }
      }
    }

    // Se queda anotado: al usuario no se le avisa porque ya descartó y no hay
    // nada que pueda hacer.
    pendientes.agregar(descarte);
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
    double? distanciaMetros,
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
              distanciaMetros: distanciaMetros,
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
