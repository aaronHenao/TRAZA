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

  PermisosService get _servicio => ref.read(permisosServiceProvider);

  @override
  EstadoPermisos build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    Future.microtask(actualizar);
    return const EstadoPermisos();
  }

  /// Vuelve a consultar al sistema. Se llama al abrir la app y al volver de
  /// los ajustes del teléfono, donde el usuario pudo cambiar los permisos.
  Future<void> actualizar() async {
    if (!_activo) return;
    final ubicacion = await _consultar('ubicación', _servicio.estadoUbicacion);
    final salud = await _consultar('salud', _servicio.estadoSalud);
    if (!_activo) return;
    state = state.copyWith(ubicacion: ubicacion, salud: salud);
  }

  /// Pide el permiso de ubicación (SCRUM-77) y devuelve cómo quedó, para que
  /// la pantalla decida qué mensaje mostrar.
  Future<EstadoPermiso> solicitarUbicacion() async {
    if (state.solicitandoUbicacion) return state.ubicacion;
    state = state.copyWith(solicitandoUbicacion: true);

    final resultado = await _pedir('ubicación', _servicio.solicitarUbicacion);

    if (_activo) {
      state = state.copyWith(ubicacion: resultado, solicitandoUbicacion: false);
    }
    return resultado;
  }

  /// Pide acceso a los datos de salud (SCRUM-78).
  Future<EstadoPermiso> solicitarSalud() async {
    if (state.solicitandoSalud) return state.salud;
    state = state.copyWith(solicitandoSalud: true);

    final resultado = await _pedir('salud', _servicio.solicitarSalud);

    if (_activo) {
      state = state.copyWith(salud: resultado, solicitandoSalud: false);
    }
    return resultado;
  }

  Future<void> instalarProveedorSalud() => _servicio.instalarProveedorSalud();

  Future<void> abrirAjustes() => _servicio.abrirAjustes();

  /// Un error del plugin (por ejemplo, una plataforma sin él) deja el permiso
  /// como desconocido y el botón sigue disponible para intentarlo.
  static Future<EstadoPermiso> _consultar(
    String permiso,
    Future<EstadoPermiso> Function() consulta,
  ) async {
    try {
      return await consulta();
    } catch (error) {
      debugPrint('No se pudo consultar el permiso de $permiso: $error');
      return EstadoPermiso.desconocido;
    }
  }

  /// Si pedirlo falla, para el usuario es lo mismo que no tenerlo.
  static Future<EstadoPermiso> _pedir(
    String permiso,
    Future<EstadoPermiso> Function() solicitud,
  ) async {
    try {
      return await solicitud();
    } catch (error) {
      debugPrint('No se pudo pedir el permiso de $permiso: $error');
      return EstadoPermiso.denegado;
    }
  }
}

final permisosProvider = NotifierProvider<PermisosNotifier, EstadoPermisos>(
  PermisosNotifier.new,
);
