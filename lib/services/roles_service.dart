import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/rol_ganado.dart';
import 'objetivos_service.dart' show SesionRequeridaException;

/// Repositorio de roles ganados que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final rolesRepositoryProvider = Provider<RolesRepository>(
  (ref) => SupabaseRolesRepository(),
);

/// Los roles que la cuenta con la sesión abierta ya desbloqueó (SCRUM-228).
///
/// `autoDispose`: al cerrar sesión las pantallas que lo observan se desmontan
/// y los roles se descartan, así la siguiente cuenta no hereda los de la
/// anterior. Es la misma razón que en `esAdministradorProvider`.
final rolesGanadosProvider = FutureProvider.autoDispose<List<RolGanado>>(
  (ref) => ref.watch(rolesRepositoryProvider).misRoles(),
);

/// Si la cuenta con la sesión abierta es Runner Experto.
///
/// Decide qué pantallas se muestran, nada más: quien impide de verdad que un
/// corredor use lo que no le corresponde es RLS, con `es_experto()`. Si la
/// consulta falla se responde que no, igual que con el rol de administrador:
/// abrir una pantalla que después no podría guardar nada sería peor.
final esExpertoProvider = FutureProvider.autoDispose<bool>((ref) async {
  final roles = await ref.watch(rolesGanadosProvider.future);
  return roles.any((ganado) => ganado.rol == RolGanable.experto);
});

/// Lectura de `roles_usuario`.
abstract interface class RolesRepository {
  /// Los roles de la cuenta con la sesión abierta, del más antiguo al más
  /// reciente. RLS solo deja ver los propios.
  Future<List<RolGanado>> misRoles();
}

class SupabaseRolesRepository implements RolesRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseRolesRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'roles_usuario';

  /// Nadie va a ganar tantos roles, pero la consulta no se deja sin tope.
  static const limite = 20;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas que
  // nunca llegan a hablar con Supabase no necesitan inicializarlo.
  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<List<RolGanado>> misRoles() async {
    // Sin sesión, RLS no devolvería nada; se corta antes para que el error
    // diga qué pasó en vez de parecer que la cuenta no tiene roles.
    final usuarioId = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (usuarioId == null) throw const SesionRequeridaException();

    final filas = await _cliente
        .from(_tabla)
        .select()
        .order('otorgado_en', ascending: true)
        .limit(limite);

    // `desdeSupabase` devuelve null para un rol que esta versión de la app no
    // conoce: se ignora en vez de romper la lista entera.
    return filas
        .map(RolGanado.desdeSupabase)
        .whereType<RolGanado>()
        .toList(growable: false);
  }
}
