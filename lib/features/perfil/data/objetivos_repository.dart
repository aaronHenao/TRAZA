import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tipo_objetivo.dart';

/// Repositorio de objetivos que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final objetivosRepositoryProvider = Provider<ObjetivosRepository>(
  (ref) => const SupabaseObjetivosRepository(),
);

/// Se lanza cuando se intenta leer o guardar sin una sesión abierta.
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
  /// Los objetivos que el usuario ya tiene guardados.
  Future<Map<TipoObjetivo, num>> cargar();

  /// Deja en la tabla exactamente los objetivos de [objetivos], borrando los
  /// que el usuario haya desmarcado.
  Future<void> guardar(Map<TipoObjetivo, num> objetivos);
}

class SupabaseObjetivosRepository implements ObjetivosRepository {
  const SupabaseObjetivosRepository();

  static const _tabla = 'objetivos';

  SupabaseClient get _cliente => Supabase.instance.client;

  @override
  Future<Map<TipoObjetivo, num>> cargar() async {
    final usuarioId = _usuarioId();

    final filas = await _cliente
        .from(_tabla)
        .select('tipo, valor_meta')
        .eq('usuario_id', usuarioId);

    return {
      for (final fila in filas)
        ?_tipoDesdeDb(fila['tipo']): _comoNumero(fila['valor_meta']),
    };
  }

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {
    final usuarioId = _usuarioId();

    // La tabla no tiene unique (usuario_id, tipo), así que en vez de un upsert
    // se reemplaza el conjunto completo. Son dos filas como máximo.
    await _cliente.from(_tabla).delete().eq('usuario_id', usuarioId);

    if (objetivos.isEmpty) return;

    await _cliente.from(_tabla).insert([
      for (final MapEntry(key: tipo, value: valor) in objetivos.entries)
        {'usuario_id': usuarioId, 'tipo': tipo.valorDb, 'valor_meta': valor},
    ]);
  }

  String _usuarioId() {
    final id = _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
    return id;
  }

  /// Un tipo desconocido en la tabla se ignora en vez de tumbar la carga.
  static TipoObjetivo? _tipoDesdeDb(Object? valor) {
    for (final tipo in TipoObjetivo.values) {
      if (tipo.valorDb == valor) return tipo;
    }
    return null;
  }

  /// `valor_meta` es `numeric`, que según el caso llega como número o como
  /// texto.
  static num _comoNumero(Object? valor) =>
      valor is num ? valor : num.parse('$valor');
}
