import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/punto_gps.dart';
import '../models/resumen_entrenamiento.dart';
import 'objetivos_service.dart' show SesionRequeridaException;

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
  /// Crea el entrenamiento que empieza (SCRUM-99) y devuelve su `id`, que
  /// pasa a ser el dueño de los puntos GPS que se registren.
  ///
  /// La fila nace `en_curso`; la cierra [finalizar] al terminar la actividad.
  /// Lanza [SesionRequeridaException] si no hay sesión abierta.
  Future<String> crear({required String tipoActividadId});

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

  /// Descarta el entrenamiento [entrenamientoId]: lo deja `cancelado` para
  /// que no quede abierto en la base.
  ///
  /// El entrenamiento descartado no se guarda, así que no lleva duración ni
  /// distancia; [fechaFin] solo deja constancia de cuándo se cerró la fila.
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  });

  /// Datos del entrenamiento [entrenamientoId] para el resumen (SCRUM-118),
  /// con su tipo de actividad y sus puntos GPS en orden.
  ///
  /// Devuelve null si no existe, no es del usuario o no está `finalizado`: el
  /// resumen nunca muestra una sesión en curso, una cancelada ni otra que no
  /// sea la pedida.
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId);
}

class SupabaseEntrenamientoRepository implements EntrenamientoRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseEntrenamientoRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'entrenamientos';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas de las
  // pantallas, que nunca llegan a hablar con Supabase, no necesitan
  // inicializarlo.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  @override
  Future<String> crear({required String tipoActividadId}) async {
    // `fecha_inicio` la pone la base con su `default now()`: es la hora del
    // servidor, que no depende de que el reloj del teléfono esté en hora.
    final fila = await _cliente
        .from(_tabla)
        .insert({
          'usuario_id': _usuarioId(),
          'tipo_actividad_id': tipoActividadId,
          'estado': 'en_curso',
        })
        // El id lo genera la base; sin pedirlo de vuelta no habría con qué
        // guardar los puntos ni cerrar el entrenamiento.
        .select('id')
        .single();

    final id = fila['id'];
    if (id is! String) {
      throw StateError('El entrenamiento creado llegó sin id: $fila');
    }
    return id;
  }

  String _usuarioId() {
    final usuarioActual = _usuarioActual;
    final id = usuarioActual != null
        ? usuarioActual()
        : _cliente.auth.currentUser?.id;
    // `entrenamientos.usuario_id` referencia a `auth.users` y su RLS exige
    // `auth.uid() = usuario_id`: sin sesión la base rechazaría la fila.
    if (id == null) throw const SesionRequeridaException();
    return id;
  }

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

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) async {
    final filas = await _cliente
        .from(_tabla)
        .update({
          'fecha_fin': fechaFin.toUtc().toIso8601String(),
          'estado': 'cancelado',
        })
        .eq('id', entrenamientoId)
        // Solo el que sigue en curso: si ya se cerró, no hay nada que
        // descartar.
        .eq('estado', 'en_curso')
        .select('id');

    if (filas.isEmpty) {
      throw EntrenamientoNoEncontradoException(entrenamientoId);
    }
  }

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) async {
    // Se pide por id, nunca "el último": así el resumen es siempre el de la
    // sesión que indica la ruta (SCRUM-122). El filtro de estado deja fuera
    // las sesiones en curso y las canceladas.
    final fila = await _cliente
        .from(_tabla)
        .select(
          'id,fecha_fin,duracion_segundos,distancia_total_m,'
          'tipos_actividad(nombre),'
          'puntos_gps(latitud,longitud,capturado_en,orden_secuencia)',
        )
        .eq('id', entrenamientoId)
        .eq('estado', 'finalizado')
        .order(
          'orden_secuencia',
          ascending: true,
          referencedTable: 'puntos_gps',
        )
        .maybeSingle();

    return fila == null ? null : resumenDesdeFila(fila);
  }

  /// Arma el resumen con la fila de `entrenamientos`, su tipo de actividad y
  /// sus puntos. Devuelve null si la fila está incompleta: un entrenamiento
  /// finalizado siempre tiene `fecha_fin` y `duracion_segundos`.
  static ResumenEntrenamiento? resumenDesdeFila(Map<String, dynamic> fila) {
    final id = fila['id'];
    final fechaFin = fila['fecha_fin'];
    final duracion = fila['duracion_segundos'];
    if (id is! String || fechaFin is! String || duracion is! num) return null;

    final tipo = fila['tipos_actividad'];
    final puntos = fila['puntos_gps'];

    return ResumenEntrenamiento(
      entrenamientoId: id,
      nombreActividad: tipo is Map && tipo['nombre'] is String
          ? tipo['nombre'] as String
          : 'Entrenamiento',
      fechaFin: DateTime.parse(fechaFin),
      duracion: Duration(seconds: duracion.toInt()),
      distanciaMetros: _comoDouble(fila['distancia_total_m']),
      puntos: [
        if (puntos is List)
          for (final punto in puntos.cast<Map<String, dynamic>>())
            PuntoGps(
              latitud: (punto['latitud'] as num).toDouble(),
              longitud: (punto['longitud'] as num).toDouble(),
              capturadoEn: DateTime.parse(punto['capturado_en'] as String),
            ),
      ],
    );
  }

  /// `distancia_total_m` es `numeric`, que según el caso llega como número o
  /// como texto.
  static double? _comoDouble(Object? valor) => switch (valor) {
    null => null,
    final num numero => numero.toDouble(),
    _ => double.tryParse('$valor'),
  };

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
