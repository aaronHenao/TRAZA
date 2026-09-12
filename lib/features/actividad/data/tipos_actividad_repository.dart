import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/tipo_actividad.dart';

/// Repositorio de tipos de actividad que usa la app. Las pruebas de la
/// pantalla lo sustituyen con `overrideWithValue`.
final tiposActividadRepositoryProvider = Provider<TiposActividadRepository>(
  (ref) => SupabaseTiposActividadRepository(),
);

/// Acceso al catálogo `tipos_actividad`.
abstract interface class TiposActividadRepository {
  /// Los tipos de actividad disponibles, en el orden en que se muestran.
  Future<List<TipoActividad>> cargar();
}

class SupabaseTiposActividadRepository implements TiposActividadRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseTiposActividadRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'tipos_actividad';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas de la
  // pantalla, que nunca llegan a hablar con Supabase, no necesitan
  // inicializarlo.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<List<TipoActividad>> cargar() async {
    // La RLS del catálogo solo deja leerlo a usuarios autenticados: sin sesión
    // la consulta devolvería una lista vacía. Mientras no haya login se usa el
    // catálogo local, que refleja lo que siembra la migración.
    if (_usuarioId() == null) return TipoActividad.catalogoLocal;

    final filas = await _cliente.from(_tabla).select('id,nombre');
    return ordenarTiposActividad([
      for (final fila in filas)
        TipoActividad(
          id: fila['id'] as String,
          nombre: fila['nombre'] as String,
        ),
    ]);
  }

  String? _usuarioId() {
    final usuarioActual = _usuarioActual;
    return usuarioActual != null
        ? usuarioActual()
        : _cliente.auth.currentUser?.id;
  }
}
