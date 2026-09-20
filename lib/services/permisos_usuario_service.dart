import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estado_permisos.dart';
import 'objetivos_service.dart' show SesionRequeridaException;

/// Repositorio de permisos que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final permisosUsuarioRepositoryProvider = Provider<PermisosUsuarioRepository>(
  (ref) => SupabasePermisosUsuarioRepository(),
);

/// Acceso a la tabla `permisos_usuario` (SCRUM-80).
abstract interface class PermisosUsuarioRepository {
  /// Deja registrado si el usuario concedió o no el permiso de [tipo].
  Future<void> guardar(TipoPermiso tipo, {required bool concedido});
}

class SupabasePermisosUsuarioRepository implements PermisosUsuarioRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabasePermisosUsuarioRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'permisos_usuario';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  // `Supabase.instance` se toca recién al usarlo, igual que en objetivos.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {
    // Una fila por usuario y tipo: el upsert se apoya en la restricción
    // unique (usuario_id, tipo_permiso) de la migración 0001.
    await _cliente.from(_tabla).upsert({
      'usuario_id': _usuarioId(),
      'tipo_permiso': tipo.valorDb,
      'concedido': concedido,
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'usuario_id,tipo_permiso');
  }

  String _usuarioId() {
    final usuarioActual = _usuarioActual;
    final id = usuarioActual != null
        ? usuarioActual()
        : _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
    return id;
  }
}
