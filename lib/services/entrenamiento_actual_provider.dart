import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ruta.dart';

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

/// La ruta oficial que se corre en el entrenamiento en curso, o null en un
/// entrenamiento libre (rutas oficiales, etapa 3).
///
/// La fija el inicio cuando el corredor sale desde "Correr esta ruta" y se
/// suelta al terminar o descartar la actividad. Con ella el mapa del
/// tracking dibuja la guía y el resumen dice qué ruta se corrió.
///
/// Regla: se limpia en todo lugar donde se limpie
/// [entrenamientoEnCursoProvider]. Si no, una salida nueva dejaría la ruta
/// pegada al siguiente entrenamiento.
class RutaEnCursoNotifier extends Notifier<Ruta?> {
  @override
  Ruta? build() => null;

  void fijar(Ruta ruta) => state = ruta;

  void limpiar() => state = null;
}

final rutaEnCursoProvider = NotifierProvider<RutaEnCursoNotifier, Ruta?>(
  RutaEnCursoNotifier.new,
);
