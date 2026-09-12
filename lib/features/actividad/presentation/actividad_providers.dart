import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tipos_actividad_repository.dart';
import '../domain/configuracion_inicio.dart';
import '../domain/tipo_actividad.dart';

/// Catálogo de tipos de actividad para los chips del inicio.
///
/// El reintento automático de Riverpod 3 está apagado a propósito: si la carga
/// falla, la pantalla ofrece un botón "Reintentar", igual que el perfil.
final tiposActividadProvider = FutureProvider<List<TipoActividad>>(
  (ref) => ref.watch(tiposActividadRepositoryProvider).cargar(),
  retry: (_, _) => null,
);

/// La actividad a realizar: la que el usuario eligió en los chips (SCRUM-92).
///
/// Mientras el usuario no toque ningún chip vale el primer tipo del catálogo,
/// igual que en el prototipo, donde "Correr" arranca marcado.
class ActividadSeleccionadaNotifier extends Notifier<TipoActividad?> {
  @override
  TipoActividad? build() {
    final tipos = ref.watch(tiposActividadProvider).value;
    return tipos == null || tipos.isEmpty ? null : tipos.first;
  }

  void seleccionar(TipoActividad tipo) => state = tipo;
}

final actividadSeleccionadaProvider =
    NotifierProvider<ActividadSeleccionadaNotifier, TipoActividad?>(
      ActividadSeleccionadaNotifier.new,
    );

/// Configuración con la que el flujo de inicio arranca el entrenamiento
/// (SCRUM-93): la del tipo elegido en los chips, o null si con lo elegido no
/// se puede iniciar (ver [ConfiguracionInicio.para]).
///
/// La consume la pantalla del entrenamiento en curso de Aaron
/// (`TrackingScreen`, que hoy solo existe en `develop`). Al traer `develop` a
/// esta rama falta registrar la ruta en `app_router.dart`:
///
/// ```dart
/// GoRoute(
///   path: Rutas.tracking,
///   builder: (context, state) => Consumer(
///     builder: (context, ref, _) => TrackingScreen(
///       nombreActividad: ref.watch(configuracionInicioProvider)!.nombreActividad,
///     ),
///   ),
/// ),
/// ```
///
/// El `!` es seguro porque el botón "Iniciar actividad" (SCRUM-96) solo debe
/// navegar a esa ruta cuando este provider no es null.
final configuracionInicioProvider = Provider<ConfiguracionInicio?>(
  (ref) => ConfiguracionInicio.para(ref.watch(actividadSeleccionadaProvider)),
);
