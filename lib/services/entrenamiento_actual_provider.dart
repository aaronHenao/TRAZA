import 'package:flutter_riverpod/flutter_riverpod.dart';

/// El entrenamiento que está en curso, mientras dura la actividad.
///
/// Lo fija el flujo de inicio al crear la fila en `entrenamientos`
/// (SCRUM-99) y se libera cuando la actividad termina o se descarta.
class EntrenamientoEnCursoNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Deja [entrenamientoId] como el entrenamiento en curso, reemplazando el
  /// anterior si lo hubiera.
  void fijar(String entrenamientoId) => state = entrenamientoId;

  /// Ya no hay entrenamiento en curso: terminó o se descartó.
  void limpiar() => state = null;
}

final entrenamientoEnCursoProvider =
    NotifierProvider<EntrenamientoEnCursoNotifier, String?>(
      EntrenamientoEnCursoNotifier.new,
    );

/// `id` del entrenamiento en curso, dueño de los puntos que se registran, o
/// null si no hay ninguno.
///
/// Es solo de lectura a propósito: quien necesite cambiarlo usa
/// [entrenamientoEnCursoProvider]. Las HU que lo consumen (el registro de
/// puntos de SCRUM-110, el cierre de SCRUM-121 y el resumen de SCRUM-117) lo
/// sustituyen en sus pruebas con `overrideWithValue`.
final entrenamientoActualProvider = Provider<String?>(
  (ref) => ref.watch(entrenamientoEnCursoProvider),
);
