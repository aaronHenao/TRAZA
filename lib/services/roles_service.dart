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

/// El rol que el corredor desbloqueó y todavía no sabe, o null si no hay
/// ninguno pendiente de anunciar (SCRUM-229).
///
/// Si hubiera varios sin anunciar se avisa del más antiguo primero, que es el
/// orden en que los ganó.
final rolPorAnunciarProvider = FutureProvider.autoDispose<RolGanado?>((
  ref,
) async {
  final roles = await ref.watch(rolesGanadosProvider.future);
  for (final ganado in roles) {
    if (!ganado.anunciado) return ganado;
  }
  return null;
});

/// Lectura de `roles_usuario` y marcado del anuncio.
abstract interface class RolesRepository {
  /// Los roles de la cuenta con la sesión abierta, del más antiguo al más
  /// reciente. RLS solo deja ver los propios.
  Future<List<RolGanado>> misRoles();

  /// Deja constancia de que al corredor ya se le avisó de [rol].
  ///
  /// Llamarla dos veces no cambia la fecha: el aviso se da una sola vez
  /// (criterio 5 de SCRUM-224).
  Future<void> marcarAnunciado(RolGanable rol);
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

  @override
  Future<void> marcarAnunciado(RolGanable rol) async {
    // La función de `0013_anuncio_rol.sql` escribe la fecha solo si estaba
    // vacía, y solo sobre las filas de la sesión abierta: el cliente no puede
    // tocar `roles_usuario` de otra forma.
    await _cliente.rpc<void>(
      'marcar_rol_anunciado',
      params: {'p_rol': rol.valorDb},
    );
  }
}
