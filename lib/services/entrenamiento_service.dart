import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositorio de entrenamientos que usa la app. Las pruebas lo sustituyen
/// con `overrideWithValue`.
final entrenamientoRepositoryProvider = Provider<EntrenamientoRepository>(
  (ref) => SupabaseEntrenamientoRepository(),
);

/// Se lanza cuando el entrenamiento que se quiere cerrar no existe o no es del
/// usuario de la sesión.
class EntrenamientoNoEncontradoException implements Exception {
  const EntrenamientoNoEncontradoException(this.entrenamientoId);

  final String entrenamientoId;

  @override
  String toString() =>
      'EntrenamientoNoEncontradoException: no se encontró el entrenamiento '
      '$entrenamientoId';
}

/// Acceso a la tabla `entrenamientos`.
abstract interface class EntrenamientoRepository {
  /// Cierra el entrenamiento [entrenamientoId] (SCRUM-121): guarda cuándo
  /// terminó, cuánto duró y la distancia recorrida, y lo deja `finalizado`.
  ///
  /// [distanciaMetros] queda vacía mientras la distancia no se calcule
  /// (SCRUM-111 y SCRUM-112).
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  });
}

class SupabaseEntrenamientoRepository implements EntrenamientoRepository {
  /// [cliente] existe para las pruebas. En la app se deja vacío y se usa el
  /// cliente global.
  SupabaseEntrenamientoRepository({SupabaseClient? cliente})
    : _clienteInyectado = cliente;

  static const _tabla = 'entrenamientos';

  final SupabaseClient? _clienteInyectado;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas de las
  // pantallas, que nunca llegan a hablar con Supabase, no necesitan
  // inicializarlo.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) async {
    // `select` devuelve las filas actualizadas. Si el id no existe o RLS no
    // deja tocar la fila, PostgREST no da error: simplemente no actualiza
    // nada. Sin esta comprobación el cierre parecería guardado sin estarlo.
    final filas = await _cliente
        .from(_tabla)
        .update(
          cambiosAlFinalizar(
            fechaFin: fechaFin,
            duracion: duracion,
            distanciaMetros: distanciaMetros,
          ),
        )
        .eq('id', entrenamientoId)
        .select('id');

    if (filas.isEmpty) {
      throw EntrenamientoNoEncontradoException(entrenamientoId);
    }
  }

  /// Columnas de `entrenamientos` que cambian al finalizar la actividad.
  static Map<String, Object?> cambiosAlFinalizar({
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) {
    return {
      'fecha_fin': fechaFin.toUtc().toIso8601String(),
      'duracion_segundos': duracion.inSeconds,
      'distancia_total_m': distanciaMetros,
      'estado': 'finalizado',
    };
  }
}
