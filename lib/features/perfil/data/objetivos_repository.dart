import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tipo_objetivo.dart';

/// Se lanza cuando se intenta guardar sin una sesión abierta.
///
/// `objetivos.usuario_id` referencia a `auth.users` y la política RLS exige
/// `auth.uid() = usuario_id`, así que sin sesión no hay nada que hacer.
class SesionRequeridaException implements Exception {
  const SesionRequeridaException();

  @override
  String toString() => 'SesionRequeridaException: no hay una sesión abierta';
}

/// Acceso a la tabla `objetivos`.
abstract interface class ObjetivosRepository {
  /// Deja en la tabla exactamente los objetivos de [objetivos], borrando los
  /// que el usuario haya desmarcado.
  Future<void> guardar(Map<TipoObjetivo, num> objetivos);
}

class SupabaseObjetivosRepository implements ObjetivosRepository {
  const SupabaseObjetivosRepository();

  static const _tabla = 'objetivos';

  SupabaseClient get _cliente => Supabase.instance.client;

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {
    final usuarioId = _cliente.auth.currentUser?.id;
    if (usuarioId == null) {
      throw const SesionRequeridaException();
    }

    // La tabla no tiene unique (usuario_id, tipo), así que en vez de un upsert
    // se reemplaza el conjunto completo. Son dos filas como máximo.
    await _cliente.from(_tabla).delete().eq('usuario_id', usuarioId);

    if (objetivos.isEmpty) return;

    await _cliente.from(_tabla).insert([
      for (final MapEntry(key: tipo, value: valor) in objetivos.entries)
        {'usuario_id': usuarioId, 'tipo': tipo.valorDb, 'valor_meta': valor},
    ]);
  }
}
