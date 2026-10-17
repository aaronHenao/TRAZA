import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ruta.dart';
// `usuarioActualProvider` vive ahí desde el foro, pero no es del foro: dice
// quién tiene la sesión abierta. Se reutiliza en vez de declarar otro, para
// que una prueba que sustituya la sesión la sustituya para toda la app.
import 'foro_service.dart' show usuarioActualProvider;

/// Repositorio de rutas que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final rutasRepositoryProvider = Provider<RutasRepository>(
  (ref) =>
      SupabaseRutasRepository(usuarioActual: ref.read(usuarioActualProvider)),
);

/// Se lanza cuando se intenta registrar una ruta sin una sesión abierta.
class SesionRequeridaParaRutasException implements Exception {
  const SesionRequeridaParaRutasException();

  @override
  String toString() =>
      'SesionRequeridaParaRutasException: no hay una sesión abierta';
}

/// Acceso a la tabla `rutas` (SCRUM-241).
abstract interface class RutasRepository {
  /// Registra [ruta] a nombre del usuario de la sesión y devuelve la fila
  /// creada.
  ///
  /// Lo que vuelve trae lo que puso la base: el nombre del autor, el estado
  /// —siempre `en_revision`, publicar manda a revisión— el punto de inicio
  /// y la distancia.
  Future<Ruta> crear(NuevaRuta ruta);
}

/// Inserta en `rutas`.
///
/// La policy de insert exige que el entrenamiento sea del usuario y esté
/// finalizado: si el insert falla por permiso, revisa eso antes que el
/// código Dart.
class SupabaseRutasRepository implements RutasRepository {
  SupabaseRutasRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const String tabla = 'rutas';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaRutasException();
    return id;
  }

  @override
  Future<Ruta> crear(NuevaRuta ruta) async {
    final usuarioId = _usuarioId();

    // Ni el nombre del autor, ni el estado, ni el inicio, ni la distancia
    // van en el insert: los pone el trigger `rutas_preparar`. Si los mandara
    // el cliente, cualquiera publicaría a nombre de otro, se saltaría la
    // revisión del experto o se inventaría los kilómetros de su ruta.
    final fila = await _cliente
        .from(tabla)
        .insert({...ruta.aSupabase(), 'autor_id': usuarioId})
        .select()
        .single();

    return Ruta.desdeSupabase(fila);
  }
}
