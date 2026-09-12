import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tipos_actividad_repository.dart';
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
/// Es lo que el flujo de inicio lee para arrancar el entrenamiento (SCRUM-93 y
/// SCRUM-96). Mientras el usuario no toque ningún chip vale el primer tipo del
/// catálogo, igual que en el prototipo, donde "Correr" arranca marcado.
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
