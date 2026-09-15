import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_permisos.dart';
import 'permisos_service.dart';
import 'permisos_usuario_service.dart';

/// Estado de los permisos de la app (SCRUM-37).
///
/// No es autoDispose: la pantalla de permisos y las de entrenamiento leen el
/// mismo estado.
class PermisosNotifier extends Notifier<EstadoPermisos> {
  /// Riverpod 2 no trae `ref.mounted`: evita publicar estado si el provider
  /// se destruyó mientras se esperaba al sistema.
  bool _activo = false;

  /// Sube al empezar y al terminar cada solicitud. Si cambia mientras
  /// [actualizar] espera al sistema, su consulta ya es vieja y no debe pisar la respuesta
  /// del usuario. En Android pasa siempre: cerrar la ventana del permiso
  /// devuelve la app al frente y eso dispara [actualizar].
  var _solicitudesUbicacion = 0;
  var _solicitudesSalud = 0;

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
    final solicitudesUbicacion = _solicitudesUbicacion;
    final solicitudesSalud = _solicitudesSalud;

    var ubicacion = await _consultar('ubicación', _servicio.estadoUbicacion);
    var salud = await _consultar('salud', _servicio.estadoSalud);
    if (!_activo) return;

    final anterior = state;
    if (solicitudesUbicacion != _solicitudesUbicacion ||
        anterior.solicitandoUbicacion) {
      ubicacion = anterior.ubicacion;
    }
    if (solicitudesSalud != _solicitudesSalud || anterior.solicitandoSalud) {
      salud = anterior.salud;
    }
    state = state.copyWith(
      ubicacion: ubicacion,
      salud: salud,
      consultado: true,
    );

    // Solo si cambió: volver a la app no debe escribir en Supabase cada vez.
    if (ubicacion != anterior.ubicacion) {
      _registrar(TipoPermiso.ubicacion, ubicacion);
    }
    if (salud != anterior.salud) _registrar(TipoPermiso.salud, salud);
  }

  /// Pide el permiso de ubicación (SCRUM-77) y devuelve cómo quedó, para que
  /// la pantalla decida qué mensaje mostrar.
  Future<EstadoPermiso> solicitarUbicacion() async {
    if (state.solicitandoUbicacion) return state.ubicacion;
    _solicitudesUbicacion++;
    state = state.copyWith(solicitandoUbicacion: true);

    final resultado = await _pedir('ubicación', _servicio.solicitarUbicacion);

    if (_activo) {
      _solicitudesUbicacion++;
      state = state.copyWith(ubicacion: resultado, solicitandoUbicacion: false);
      _registrar(TipoPermiso.ubicacion, resultado);
    }
    return resultado;
  }

  /// Pide acceso a los datos de salud (SCRUM-78).
  Future<EstadoPermiso> solicitarSalud() async {
    if (state.solicitandoSalud) return state.salud;
    _solicitudesSalud++;
    state = state.copyWith(solicitandoSalud: true);

    final resultado = await _pedir('salud', _servicio.solicitarSalud);

    if (_activo) {
      _solicitudesSalud++;
      state = state.copyWith(salud: resultado, solicitandoSalud: false);
      _registrar(TipoPermiso.salud, resultado);
    }
    return resultado;
  }

  Future<void> instalarProveedorSalud() => _servicio.instalarProveedorSalud();

  Future<void> abrirAjustes() => _servicio.abrirAjustes();

  /// Guarda la decisión en `permisos_usuario` (SCRUM-80).
  ///
  /// No se espera: la pantalla responde de inmediato y, si falla (sin sesión o
  /// sin red), el permiso del teléfono sigue valiendo igual. La próxima vez
  /// que cambie se vuelve a intentar.
  void _registrar(TipoPermiso tipo, EstadoPermiso estado) {
    final concedido = switch (estado) {
      EstadoPermiso.concedido => true,
      EstadoPermiso.denegado || EstadoPermiso.bloqueado => false,
      // No hay una decisión del usuario que guardar.
      EstadoPermiso.desconocido || EstadoPermiso.noDisponible => null,
    };
    if (concedido == null) return;

    final repositorio = ref.read(permisosUsuarioRepositoryProvider);
    unawaited(
      repositorio.guardar(tipo, concedido: concedido).catchError((
        Object error,
      ) {
        debugPrint('No se pudo guardar el permiso de ${tipo.valorDb}: $error');
      }),
    );
  }

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
