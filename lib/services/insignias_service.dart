import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/insignia.dart';
import 'objetivos_service.dart' show SesionRequeridaException;

/// Repositorio de insignias que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final insigniasRepositoryProvider = Provider<InsigniasRepository>(
  (ref) => SupabaseInsigniasRepository(),
);

/// Lectura de las insignias (SCRUM-193).
///
/// Solo lectura: las otorga el trigger de `0010_insignias.sql` cuando entra
/// XP, y el cliente no puede escribirlas.
abstract interface class InsigniasRepository {
  /// Todo el catálogo, de menor a mayor XP requerida, marcando las que el
  /// corredor ya obtuvo.
  Future<List<Insignia>> listar();
}

class SupabaseInsigniasRepository implements InsigniasRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseInsigniasRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'insignias';

  /// Una sola consulta: el catálogo con la obtención embebida. RLS filtra
  /// `insignias_usuario` a las del corredor, así que no hace falta filtrar
  /// aquí por usuario.
  static const _columnas =
      'id, nombre, descripcion, icono, xp_requerida, '
      'insignias_usuario(fecha_obtencion)';

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas que
  // nunca llegan a hablar con Supabase no necesitan inicializarlo.
  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  // Sin sesión, RLS mostraría el catálogo sin ninguna obtenida; se corta
  // antes para que el error diga qué pasó.
  void _exigirSesion() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
  }

  @override
  Future<List<Insignia>> listar() async {
    _exigirSesion();

    final filas = await _cliente
        .from(_tabla)
        .select(_columnas)
        .order('xp_requerida', ascending: true);

    return filas.map(Insignia.desdeSupabase).toList();
  }
}
