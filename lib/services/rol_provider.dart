import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositorio del rol que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final rolRepositoryProvider = Provider<RolRepository>(
  (ref) => SupabaseRolRepository(),
);

/// Si la cuenta con la sesión abierta administra retos (SCRUM-137).
///
/// Decide qué pantallas se muestran, nada más: quien impide que un corredor
/// escriba en `retos` es RLS. Si la consulta falla, se responde que no —
/// tratar un fallo de red como "es administrador" abriría una pantalla de
/// gestión que después no podría guardar nada.
///
/// `autoDispose`: al cerrar sesión las pantallas que lo observan se
/// desmontan y el rol se descarta, así la siguiente cuenta no hereda el de la
/// anterior.
final esAdministradorProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(rolRepositoryProvider).esAdministrador(),
);

/// Lectura de `perfiles.rol`.
abstract interface class RolRepository {
  Future<bool> esAdministrador();
}

class SupabaseRolRepository implements RolRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseRolRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'perfiles';
  static const _rolAdmin = 'admin';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<bool> esAdministrador() async {
    final usuarioId = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    // Sin sesión no hay rol que leer, y el router ya manda al login.
    if (usuarioId == null) return false;

    try {
      final fila = await _cliente
          .from(_tabla)
          .select('rol')
          .eq('id', usuarioId)
          .maybeSingle();

      return fila?['rol'] == _rolAdmin;
    } catch (error) {
      debugPrint('No se pudo leer el rol del usuario: $error');
      return false;
    }
  }
}
