import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/objetivos_repository.dart';
import '../domain/tipo_objetivo.dart';
import 'perfil_state.dart';

/// Maneja los objetivos del perfil: qué está marcado (SCRUM-86), el valor de
/// cada uno (SCRUM-87 y SCRUM-88) y el guardado en la tabla `objetivos`
/// (SCRUM-89).
class PerfilNotifier extends Notifier<PerfilState> {
  @override
  PerfilState build() => PerfilState.inicial();

  /// Marca o desmarca un objetivo. Se pueden tener varios activos a la vez.
  void alternar(TipoObjetivo tipo) {
    final seleccionados = {...state.seleccionados};
    if (!seleccionados.remove(tipo)) {
      seleccionados.add(tipo);
    }
    state = state.copyWith(seleccionados: seleccionados);
  }

  void actualizarValor(TipoObjetivo tipo, String texto) {
    if (state.textoDe(tipo) == texto) return;
    state = state.copyWith(textos: {...state.textos, tipo: texto});
  }

  /// Guarda los objetivos marcados en el perfil del usuario.
  ///
  /// Devuelve null si salió bien, o el mensaje de error a mostrar.
  Future<String?> guardarObjetivos() async {
    if (state.sinObjetivos) return 'Selecciona al menos un objetivo';
    if (state.hayValoresInvalidos) return 'Revisa los valores de tus objetivos';

    state = state.copyWith(guardando: true);
    try {
      await ref
          .read(objetivosRepositoryProvider)
          .guardar(state.objetivosAGuardar);
      return null;
    } on SesionRequeridaException {
      return 'Inicia sesión para guardar tus objetivos';
    } catch (error) {
      debugPrint('No se pudieron guardar los objetivos: $error');
      return 'No se pudieron guardar tus objetivos. '
          'Revisa tu conexión e inténtalo de nuevo.';
    } finally {
      state = state.copyWith(guardando: false);
    }
  }
}

final perfilProvider = NotifierProvider<PerfilNotifier, PerfilState>(
  PerfilNotifier.new,
);
