import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/historial_entrenamientos.dart';
import '../models/resumen_entrenamiento.dart';
import 'entrenamiento_service.dart';
import 'objetivos_service.dart' show SesionRequeridaException;

/// Repositorio del historial que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final historialRepositoryProvider = Provider<HistorialRepository>(
  (ref) => SupabaseHistorialRepository(),
);

/// Entrenamientos anteriores del usuario (SCRUM-124), del más reciente al más
/// antiguo.
///
/// `autoDispose`: cada vez que se abre el historial se consulta de nuevo, así
/// aparece el entrenamiento que se acaba de terminar.
final historialProvider =
    FutureProvider.autoDispose<List<ResumenEntrenamiento>>(
      (ref) => ref.watch(historialRepositoryProvider).cargar(),
    );

/// Lectura de los entrenamientos finalizados del usuario.
abstract interface class HistorialRepository {
  Future<List<ResumenEntrenamiento>> cargar();
}

class SupabaseHistorialRepository implements HistorialRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseHistorialRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  /// Suficiente para meses de entrenamientos sin traer la tabla entera.
  static const limite = 100;

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<List<ResumenEntrenamiento>> cargar() async {
    // RLS ya filtra por usuario; el filtro explícito deja clara la intención
    // y evita depender solo de la política.
    final filas = await _cliente
        .from('entrenamientos')
        // Sin puntos GPS: la lista no los necesita y el resumen los carga al
        // abrir cada sesión.
        .select(
          'id,fecha_fin,duracion_segundos,distancia_total_m,'
          'tipos_actividad(nombre)',
        )
        .eq('usuario_id', _usuarioId())
        // Ni las sesiones en curso ni las canceladas son historial.
        .eq('estado', 'finalizado')
        .order('fecha_fin', ascending: false)
        .limit(limite);

    return prepararHistorial(
      filas.map(SupabaseEntrenamientoRepository.resumenDesdeFila),
    );
  }

  String _usuarioId() {
    final usuarioActual = _usuarioActual;
    final id = usuarioActual != null
        ? usuarioActual()
        : _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
    return id;
  }
}
