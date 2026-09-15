import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_permisos.dart';
import 'permisos_service.dart';

/// Estado de los permisos de la app (SCRUM-37).
///
/// No es autoDispose: la pantalla de permisos y las de entrenamiento leen el
/// mismo estado.
class PermisosNotifier extends Notifier<EstadoPermisos> {
  /// Riverpod 2 no trae `ref.mounted`: evita publicar estado si el provider
  /// se destruyó mientras se esperaba al sistema.
  bool _activo = false;

  @override
  EstadoPermisos build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    Future.microtask(actualizar);
    return const EstadoPermisos();
  }

  /// Vuelve a consultar al sistema. Se llama al abrir la app y al volver de
  /// los ajustes del teléfono, donde el usuario pudo cambiar el permiso.
  Future<void> actualizar() async {
    if (!_activo) return;
    try {
      final ubicacion = await ref
          .read(permisosServiceProvider)
          .estadoUbicacion();
      if (!_activo) return;
      state = state.copyWith(ubicacion: ubicacion);
    } catch (error) {
      // Por ejemplo, una plataforma sin el plugin. Se deja como desconocido y
      // el botón sigue disponible para intentarlo.
      debugPrint('No se pudo consultar el permiso de ubicación: $error');
    }
  }

  /// Pide el permiso de ubicación (SCRUM-77) y devuelve cómo quedó, para que
  /// la pantalla decida qué mensaje mostrar.
  Future<EstadoPermiso> solicitarUbicacion() async {
    if (state.solicitandoUbicacion) return state.ubicacion;
    state = state.copyWith(solicitandoUbicacion: true);

    var resultado = EstadoPermiso.denegado;
    try {
      resultado = await ref.read(permisosServiceProvider).solicitarUbicacion();
    } catch (error) {
      debugPrint('No se pudo pedir el permiso de ubicación: $error');
    }

    if (_activo) {
      state = state.copyWith(ubicacion: resultado, solicitandoUbicacion: false);
    }
    return resultado;
  }

  Future<void> abrirAjustes() =>
      ref.read(permisosServiceProvider).abrirAjustes();
}

final permisosProvider = NotifierProvider<PermisosNotifier, EstadoPermisos>(
  PermisosNotifier.new,
);
