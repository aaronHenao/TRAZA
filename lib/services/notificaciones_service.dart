import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notificacion.dart';
// `usuarioActualProvider` dice quién tiene la sesión abierta. Vive en el
// foro, que fue quien lo necesitó primero, y se reutiliza para que una prueba
// que sustituya la sesión la sustituya para toda la app.
import 'foro_service.dart' show usuarioActualProvider;

/// Repositorio de notificaciones que usa la app. Las pruebas lo sustituyen
/// con `overrideWithValue`.
final notificacionesRepositoryProvider = Provider<NotificacionesRepository>(
  (ref) => SupabaseNotificacionesRepository(
    usuarioActual: ref.read(usuarioActualProvider),
  ),
);

/// Se lanza cuando se piden notificaciones sin una sesión abierta.
class SesionRequeridaParaNotificacionesException implements Exception {
  const SesionRequeridaParaNotificacionesException();

  @override
  String toString() =>
      'SesionRequeridaParaNotificacionesException: no hay una sesión abierta';
}

/// Acceso a la tabla `notificaciones` (SCRUM-241, SCRUM-242).
///
/// Solo lectura y marcar como leídas: las notificaciones las crea la base
/// cuando pasa algo, no el cliente.
abstract interface class NotificacionesRepository {
  /// Las del usuario de la sesión, de la más reciente a la más antigua.
  Future<List<Notificacion>> mias();

  /// Cuántas tiene sin leer, para el contador de la campana.
  Future<int> sinLeer();

  /// Marca como leídas todas las que le quedaban sin leer.
  Future<void> marcarTodasLeidas();
}

class SupabaseNotificacionesRepository implements NotificacionesRepository {
  SupabaseNotificacionesRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const String tabla = 'notificaciones';

  /// Cuántas se traen de una vez. La bandeja es un historial de avisos, no
  /// un archivo: con las últimas cincuenta sobra.
  static const limite = 50;

  /// Tope del contador. Pasado de ahí la campana dice "9+", así que contar
  /// más no cambia nada de lo que se ve.
  static const limiteContador = 99;

  static const _columnas =
      'id,tipo,titulo,mensaje,entidad_id,leida_en,fecha_creacion';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaNotificacionesException();
    return id;
  }

  @override
  Future<List<Notificacion>> mias() async {
    final usuarioId = _usuarioId();

    final filas = await _cliente
        .from(tabla)
        .select(_columnas)
        .eq('usuario_id', usuarioId)
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    // Las de un tipo que esta versión no conoce se quedan fuera en vez de
    // tumbar la bandeja entera.
    return [for (final fila in filas) ?Notificacion.desdeSupabase(fila)];
  }

  @override
  Future<int> sinLeer() async {
    final usuarioId = _usuarioId();

    final filas = await _cliente
        .from(tabla)
        .select('id')
        .eq('usuario_id', usuarioId)
        .isFilter('leida_en', null)
        .limit(limiteContador);

    return filas.length;
  }

  @override
  Future<void> marcarTodasLeidas() async {
    final usuarioId = _usuarioId();

    // Solo las que no lo estaban: así no se reescribe la fecha de las que ya
    // había leído. El trigger `notificaciones_solo_leida` no deja cambiar
    // nada más que esta columna.
    await _cliente
        .from(tabla)
        .update({'leida_en': DateTime.now().toUtc().toIso8601String()})
        .eq('usuario_id', usuarioId)
        .isFilter('leida_en', null);
  }
}
