import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recompensa.dart';
import 'retos_service.dart' show SoloAdministradorException;

/// Repositorio de recompensas que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final recompensasRepositoryProvider = Provider<RecompensasRepository>(
  (ref) => SupabaseRecompensasRepository(),
);

/// Se lanza cuando se intenta usar las recompensas sin una sesión abierta.
class SesionRequeridaParaRecompensasException implements Exception {
  const SesionRequeridaParaRecompensasException();

  @override
  String toString() =>
      'SesionRequeridaParaRecompensasException: no hay una sesión abierta';
}

/// Se lanza cuando la base rechaza los datos de la recompensa.
///
/// No debería ocurrir: `BorradorRecompensa` valida las mismas reglas antes. Si
/// llega aquí, los `check` de la tabla y la validación de Dart se
/// desalinearon.
class DatosDeRecompensaInvalidosException implements Exception {
  const DatosDeRecompensaInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDeRecompensaInvalidosException: $detalle';
}

/// Acceso a la tabla `recompensas` (SCRUM-374).
abstract interface class RecompensasRepository {
  /// Registra [recompensa] y devuelve la fila que guardó la base, con su id.
  ///
  /// Lanza [SoloAdministradorException] si la cuenta no es administradora.
  Future<Recompensa> crear(NuevaRecompensa recompensa);

  /// Lo que ve el corredor: las disponibles, de la que menos puntos cuesta a
  /// la que más (criterio 3).
  Future<List<Recompensa>> catalogo();

  /// Todas, disponibles o no, para la gestión del administrador. La más
  /// reciente primero.
  Future<List<Recompensa>> todas();
}

class SupabaseRecompensasRepository implements RecompensasRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseRecompensasRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'recompensas';

  static const _rlsDenegado = '42501';
  static const _restriccionIncumplida = '23514';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  void _exigirSesion() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaRecompensasException();
  }

  @override
  Future<Recompensa> crear(NuevaRecompensa recompensa) async {
    _exigirSesion();

    try {
      final fila = await _cliente
          .from(_tabla)
          .insert(recompensa.aSupabase())
          .select()
          .single();

      return Recompensa.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // La policy de insert exige es_admin(); sin ese rol, Postgres responde
      // que la fila viola la seguridad a nivel de fila.
      if (e.code == _rlsDenegado) throw const SoloAdministradorException();
      if (e.code == _restriccionIncumplida) {
        throw DatosDeRecompensaInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<Recompensa>> catalogo() async {
    _exigirSesion();

    // El filtro va aunque RLS ya lo limite: al administrador la policy le
    // deja ver también las que no están disponibles.
    final filas = await _cliente
        .from(_tabla)
        .select()
        .eq('disponible', true)
        // `ascending` va explícito: el default de `order` es descendente.
        .order('puntos_requeridos', ascending: true);

    return filas.map(Recompensa.desdeSupabase).toList();
  }

  @override
  Future<List<Recompensa>> todas() async {
    _exigirSesion();

    final filas = await _cliente
        .from(_tabla)
        .select()
        .order('fecha_creacion', ascending: false);

    return filas.map(Recompensa.desdeSupabase).toList();
  }
}
