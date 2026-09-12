import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/objetivos_repository.dart';
import '../domain/tipo_objetivo.dart';
import 'perfil_state.dart';

/// Maneja los objetivos del perfil: qué está marcado (SCRUM-86), el valor de
/// cada uno (SCRUM-87 y SCRUM-88), el guardado en la tabla `objetivos`
/// (SCRUM-89) y la precarga de los que ya estaban guardados (SCRUM-90).
class PerfilNotifier extends Notifier<PerfilState> {
  /// Si el provider sigue vivo. Riverpod 2 no trae `ref.mounted`, así que se
  /// lleva a mano: evita tocar el estado si el provider se destruyó mientras
  /// se esperaba a Supabase.
  bool _activo = false;

  @override
  PerfilState build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    // La carga arranca en cuanto el estado inicial queda listo.
    Future.microtask(cargarObjetivos);
    return PerfilState.inicial();
  }

  /// Trae los objetivos que el usuario ya tenía y precarga la pantalla.
  Future<void> cargarObjetivos() async {
    if (!_activo) return;
    if (state.carga != EstadoCarga.cargando) {
      state = state.copyWith(carga: EstadoCarga.cargando);
    }

    try {
      final guardados = await ref.read(objetivosRepositoryProvider).cargar();
      if (!_activo) return;
      state = state.conObjetivosGuardados(guardados);
    } on SesionRequeridaException {
      // Sin sesión no hay nada que precargar: se muestran los valores por
      // defecto y el guardado ya avisa por su cuenta.
      if (!_activo) return;
      state = state.copyWith(carga: EstadoCarga.listo);
    } catch (error) {
      debugPrint('No se pudieron cargar los objetivos: $error');
      if (!_activo) return;
      state = state.copyWith(carga: EstadoCarga.error);
    }
  }

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
      if (_activo) {
        state = state.copyWith(guardando: false);
      }
    }
  }
}

final perfilProvider = NotifierProvider<PerfilNotifier, PerfilState>(
  PerfilNotifier.new,
);
