import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nuevo_reto.dart';
import '../models/reto.dart';

/// Repositorio de retos que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final retosRepositoryProvider = Provider<RetosRepository>(
  (ref) => SupabaseRetosRepository(),
);

/// Se lanza cuando se intenta administrar retos sin una sesión abierta.
class SesionRequeridaParaRetosException implements Exception {
  const SesionRequeridaParaRetosException();

  @override
  String toString() =>
      'SesionRequeridaParaRetosException: no hay una sesión abierta';
}

/// Se lanza cuando Postgres rechaza la operación por Row Level Security: la
/// cuenta tiene sesión, pero no es la del administrador.
///
/// Es la barrera de verdad. La app decide qué pantallas muestra según
/// `perfiles.rol`, pero con la publishable key cualquiera puede llamar a la
/// API; si la única comprobación estuviera en Dart, no habría ninguna.
class SoloAdministradorException implements Exception {
  const SoloAdministradorException();

  @override
  String toString() =>
      'SoloAdministradorException: la cuenta no tiene rol de administrador';
}

/// Se lanza cuando la base rechaza los datos del reto.
///
/// No debería ocurrir: `BorradorReto` valida las mismas reglas antes. Si llega
/// aquí, es que las restricciones de la tabla y la validación de Dart se
/// desalinearon, y conviene que se note.
class DatosDeRetoInvalidosException implements Exception {
  const DatosDeRetoInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDeRetoInvalidosException: $detalle';
}

/// Acceso a la tabla `retos`.
abstract interface class RetosRepository {
  /// Registra [reto] y devuelve la fila creada (SCRUM-143).
  ///
  /// Lo que vuelve trae el id y el estado que puso la base, no los que mandó
  /// el cliente.
  Future<Reto> crear(NuevoReto reto);
}

class SupabaseRetosRepository implements RetosRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseRetosRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'retos';

  /// Códigos de error de Postgres que hay que distinguir.
  static const _rlsDenegado = '42501';
  static const _restriccionIncumplida = '23514';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas que
  // nunca llegan a hablar con Supabase no necesitan inicializarlo.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id =
        _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaRetosException();
    return id;
  }

  @override
  Future<Reto> crear(NuevoReto reto) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tabla)
          // `estado` no va: lo pone el default 'activo' de la tabla
          // (SCRUM-145). Si el cliente lo enviara podría nacer retirado.
          .insert({...reto.aSupabase(), 'creado_por': usuarioId})
          // Se devuelve la fila completa para conocer el id y el estado que
          // asignó la base, en vez de darlos por supuestos.
          .select()
          .single();

      return Reto.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // La policy de insert exige es_admin(); sin ese rol, Postgres responde
      // que la fila viola la seguridad a nivel de fila.
      if (e.code == _rlsDenegado) throw const SoloAdministradorException();
      if (e.code == _restriccionIncumplida) {
        throw DatosDeRetoInvalidosException(e.message);
      }
      rethrow;
    }
  }
}
