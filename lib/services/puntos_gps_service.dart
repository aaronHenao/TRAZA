import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/punto_pendiente.dart';

/// Persistencia de los puntos GPS de un entrenamiento (SCRUM-110).
///
/// Los puntos se guardan en disco según se capturan y se envían por lotes
/// durante la actividad (SCRUM-292). Antes se acumulaban en memoria y se
/// subían todos al finalizar: una caída de red en ese momento se llevaba el
/// recorrido entero.
///
/// La app escribe en Supabase; las pruebas inyectan un repositorio falso.
abstract class RepositorioPuntosGps {
  /// Guarda [puntos] como filas de `puntos_gps`, en una sola operación.
  ///
  /// Vienen ya numerados: cada uno trae su `orden_secuencia` y su `tramo`,
  /// decididos al capturarlo. Los que la base ya tenga se descartan sin
  /// error, así que reenviar un lote que llegó a entrar no duplica nada ni
  /// falla (índice único de `0053`).
  Future<void> guardarLote({
    required String entrenamientoId,
    required List<PuntoPendiente> puntos,
  });
}

/// Inserta en lote en la tabla `puntos_gps`.
///
/// El RLS de la tabla exige que el `entrenamiento` pertenezca al usuario
/// autenticado; si el insert devuelve error de permiso, revisa eso antes
/// que el código Dart.
class RepositorioPuntosGpsSupabase implements RepositorioPuntosGps {
  const RepositorioPuntosGpsSupabase(this._cliente);

  final SupabaseClient _cliente;

  static const String tabla = 'puntos_gps';

  /// Lo que identifica un punto: su entrenamiento y su posición en él.
  static const String conflicto = 'entrenamiento_id,orden_secuencia';

  @override
  Future<void> guardarLote({
    required String entrenamientoId,
    required List<PuntoPendiente> puntos,
  }) {
    if (puntos.isEmpty) return Future.value();

    return _cliente
        .from(tabla)
        .upsert(
          filasPara(entrenamientoId: entrenamientoId, puntos: puntos),
          onConflict: conflicto,
          // `do nothing`: lo que ya está guardado se queda como está. Un
          // reenvío no reescribe ni falla.
          ignoreDuplicates: true,
        );
  }

  /// Una fila por punto, con el orden y el tramo que ya traen.
  static List<Map<String, Object>> filasPara({
    required String entrenamientoId,
    required List<PuntoPendiente> puntos,
  }) => [
    for (final punto in puntos)
      filaPara(entrenamientoId: entrenamientoId, punto: punto),
  ];

  /// Fila con las columnas de `puntos_gps` (sin altitud, a propósito).
  static Map<String, Object> filaPara({
    required String entrenamientoId,
    required PuntoPendiente punto,
  }) {
    return {
      'entrenamiento_id': entrenamientoId,
      'latitud': punto.latitud,
      'longitud': punto.longitud,
      'capturado_en': punto.capturadoEn.toUtc().toIso8601String(),
      'orden_secuencia': punto.orden,
      // Requiere la migración 0007 (BUG-005).
      'tramo': punto.tramo,
    };
  }
}
