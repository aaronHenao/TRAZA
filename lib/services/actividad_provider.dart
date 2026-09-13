import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tipos_actividad_service.dart';
import '../models/configuracion_inicio.dart';
import '../models/tipo_actividad.dart';

/// Catálogo de tipos de actividad para los chips del inicio.
///
/// Si la carga falla, la pantalla ofrece un botón "Reintentar", igual que el
/// perfil.
final tiposActividadProvider = FutureProvider<List<TipoActividad>>(
  (ref) => ref.watch(tiposActividadRepositoryProvider).cargar(),
);

/// La actividad a realizar: la que el usuario eligió en los chips (SCRUM-92).
///
/// Mientras el usuario no toque ningún chip vale el primer tipo del catálogo,
/// igual que en el prototipo, donde "Correr" arranca marcado.
class ActividadSeleccionadaNotifier extends Notifier<TipoActividad?> {
  @override
  TipoActividad? build() {
    // `valueOrNull` y no `value`: en Riverpod 2, `value` relanza el error si
    // la carga del catálogo falló, y aquí eso solo significa "sin actividad".
    final tipos = ref.watch(tiposActividadProvider).valueOrNull;
    return tipos == null || tipos.isEmpty ? null : tipos.first;
  }

  /// Cambia la actividad a realizar, reemplazando la anterior.
  ///
  /// Solo se puede antes de iniciar (SCRUM-94): con un entrenamiento en curso
  /// la actividad queda fija y la llamada no hace nada.
  void seleccionar(TipoActividad tipo) {
    if (ref.read(actividadIniciadaProvider)) return;
    state = tipo;
  }
}

final actividadSeleccionadaProvider =
    NotifierProvider<ActividadSeleccionadaNotifier, TipoActividad?>(
      ActividadSeleccionadaNotifier.new,
    );

/// Configuración con la que el flujo de inicio arranca el entrenamiento
/// (SCRUM-93): la del tipo elegido en los chips, o null si con lo elegido no
/// se puede iniciar (ver [ConfiguracionInicio.para]).
///
/// La usan la ruta `/tracking` (`TrackingConActividadElegida`), que muestra la
/// actividad en la pantalla del entrenamiento en curso de Aaron, y el flujo de
/// inicio (SCRUM-99), que crea el entrenamiento con `tipoActividadId` y guarda
/// el id nuevo en `entrenamientoActualProvider`.
final configuracionInicioProvider = Provider<ConfiguracionInicio?>(
  (ref) => ConfiguracionInicio.para(ref.watch(actividadSeleccionadaProvider)),
);

/// Si ya empezó un entrenamiento con la actividad elegida (SCRUM-94).
///
/// Mientras sea true la actividad no se puede cambiar. El flujo de inicio la
/// marca al arrancar y la libera cuando el entrenamiento termina:
///
/// ```dart
/// // SCRUM-96, al pulsar "Iniciar actividad". Con `push`, y no `go`, la
/// // pantalla vuelve al inicio al finalizar o cancelar (usa `maybePop`):
/// ref.read(actividadIniciadaProvider.notifier).marcarIniciada();
/// context.push('/tracking');
///
/// // Al finalizar o cancelar (`TrackingScreen.onFinalizar` y `onCancelar`):
/// ref.read(actividadIniciadaProvider.notifier).marcarTerminada();
/// ```
class ActividadIniciadaNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Fija la actividad elegida para el entrenamiento que empieza.
  ///
  /// Lanza [StateError] si no hay configuración de inicio: sin ella no hay
  /// entrenamiento posible, así que llamarla sería un error de quien la usa.
  void marcarIniciada() {
    if (ref.read(configuracionInicioProvider) == null) {
      throw StateError('No se puede iniciar sin configuración de inicio');
    }
    state = true;
  }

  /// Libera la actividad: el entrenamiento terminó o se canceló.
  void marcarTerminada() => state = false;
}

final actividadIniciadaProvider =
    NotifierProvider<ActividadIniciadaNotifier, bool>(
      ActividadIniciadaNotifier.new,
    );
