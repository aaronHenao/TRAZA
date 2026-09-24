import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nivel.dart';
import '../models/nuevo_nivel.dart';
import 'objetivos_service.dart' show SesionRequeridaException;
import 'retos_service.dart' show SoloAdministradorException;

/// Repositorio de niveles que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final nivelesRepositoryProvider = Provider<NivelesRepository>(
  (ref) => SupabaseNivelesRepository(),
);

/// Se lanza cuando ya existe un nivel con ese nombre o con ese umbral.
///
/// El umbral repetido es el solapamiento que prohíbe SCRUM-177: dos niveles no
/// pueden empezar en la misma experiencia. El formulario avisa antes
/// (SCRUM-181) y puede decir con cuál choca; esto es la última palabra, por si
/// alguien registró uno igual mientras tanto.
class NivelDuplicadoException implements Exception {
  const NivelDuplicadoException.porNombre() : esElNombre = true;
  const NivelDuplicadoException.porUmbral() : esElNombre = false;

  /// true si lo repetido es el nombre; false si es el umbral.
  final bool esElNombre;

  @override
  String toString() =>
      'NivelDuplicadoException: ya existe un nivel con ese '
      '${esElNombre ? 'nombre' : 'umbral'}';
}

/// Se lanza cuando la base rechaza los datos del nivel.
///
/// No debería ocurrir: el formulario valida las mismas reglas antes. Si llega
/// aquí, es que las restricciones de la tabla y la validación de Dart se
/// desalinearon, y conviene que se note.
class DatosDeNivelInvalidosException implements Exception {
  const DatosDeNivelInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDeNivelInvalidosException: $detalle';
}

/// Acceso a la tabla `niveles`.
abstract interface class NivelesRepository {
  /// Registra [nivel] y devuelve la fila creada.
  ///
  /// Lo que vuelve trae el id que puso la base, no uno inventado por el
  /// cliente.
  Future<Nivel> crear(NuevoNivel nivel);

  /// Los niveles registrados, del umbral más bajo al más alto.
  ///
  /// Ese orden es el que pide el criterio 1 de SCRUM-177 para el listado, y el
  /// que necesita la progresión del corredor (SCRUM-178) para saber cuál es su
  /// nivel y cuál el siguiente.
  Future<List<Nivel>> listar();
}

class SupabaseNivelesRepository implements NivelesRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseNivelesRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'niveles';

  /// De sobra para una progresión: nadie define más niveles que estos.
  static const limite = 100;

  /// Códigos de error de Postgres que hay que distinguir.
  static const _rlsDenegado = '42501';
  static const _valorDuplicado = '23505';
  static const _restriccionIncumplida = '23514';

  /// Índice único del nombre en `0007_niveles.sql`. El mensaje de Postgres lo
  /// nombra, y así se sabe si lo repetido fue el nombre o el umbral.
  static const _indiceNombreUnico = 'niveles_nombre_unico_idx';

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas que
  // nunca llegan a hablar con Supabase no necesitan inicializarlo.
  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
    return id;
  }

  @override
  Future<Nivel> crear(NuevoNivel nivel) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tabla)
          .insert({...nivel.aSupabase(), 'creado_por': usuarioId})
          // Se pide la fila de vuelta para conocer el id que asignó la base,
          // en vez de darlo por supuesto.
          .select()
          .single();

      return Nivel.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // La policy de insert exige es_admin(); sin ese rol, Postgres responde
      // que la fila viola la seguridad a nivel de fila.
      if (e.code == _rlsDenegado) throw const SoloAdministradorException();
      if (e.code == _valorDuplicado) {
        throw e.message.contains(_indiceNombreUnico)
            ? const NivelDuplicadoException.porNombre()
            : const NivelDuplicadoException.porUmbral();
      }
      if (e.code == _restriccionIncumplida) {
        throw DatosDeNivelInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<Nivel>> listar() async {
    // Sin sesión, RLS no devolvería nada; se corta antes para que el error
    // diga qué pasó en vez de mostrar una lista vacía.
    _usuarioId();

    final filas = await _cliente
        .from(_tabla)
        .select()
        .order('umbral_experiencia', ascending: true)
        .limit(limite);

    return filas.map(Nivel.desdeSupabase).toList();
  }
}
