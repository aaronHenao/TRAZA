import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tipo_objetivo.dart';

/// Repositorio de objetivos que usa la app. Las pruebas de la pantalla lo
/// sustituyen con `overrideWithValue`.
final objetivosRepositoryProvider = Provider<ObjetivosRepository>(
  (ref) => SupabaseObjetivosRepository(),
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
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseObjetivosRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'objetivos';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas de la
  // pantalla, que nunca llegan a hablar con Supabase, no necesitan
  // inicializarlo.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<Map<TipoObjetivo, num>> cargar() async {
    final usuarioId = _usuarioId();

    final filas = await _cliente
        .from(_tabla)
        .select('tipo,valor_meta')
        .eq('usuario_id', usuarioId);

    return {
      for (final fila in filas)
        ?_tipoDesdeDb(fila['tipo']): _comoNumero(fila['valor_meta']),
    };
  }

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {
    final usuarioId = _usuarioId();

    // Primero se escribe y después se borra, nunca al revés: si el borrado
    // falla el usuario acaba con un objetivo de más, pero jamás con ninguno.
    // El upsert se apoya en la restricción unique (usuario_id, tipo) que crea
    // la migración 0003.
    if (objetivos.isNotEmpty) {
      await _cliente
          .from(_tabla)
          .upsert([
            for (final MapEntry(key: tipo, value: valor) in objetivos.entries)
              {
                'usuario_id': usuarioId,
                'tipo': tipo.valorDb,
                'valor_meta': valor,
              },
          ], onConflict: 'usuario_id,tipo');
    }

    // Los tipos que el usuario desmarcó. Son dos como máximo, así que se
    // borran uno por uno en vez de armar un filtro `not in`.
    for (final tipo in TipoObjetivo.values) {
      if (objetivos.containsKey(tipo)) continue;
      await _cliente
          .from(_tabla)
          .delete()
          .eq('usuario_id', usuarioId)
          .eq('tipo', tipo.valorDb);
    }
  }

  String _usuarioId() {
    final usuarioActual = _usuarioActual;
    final id = usuarioActual != null
        ? usuarioActual()
        : _cliente.auth.currentUser?.id;
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
