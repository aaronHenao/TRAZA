import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/punto_gps.dart';

/// Persistencia de los puntos GPS de un entrenamiento (SCRUM-110).
///
/// Durante la actividad los puntos se acumulan en local; al finalizar se
/// sincronizan todos de una vez. La app escribe en Supabase; las pruebas
/// inyectan un repositorio falso.
abstract class RepositorioPuntosGps {
  /// Guarda [puntos] como filas de `puntos_gps`, en una sola operación.
  /// `orden_secuencia` es la posición de cada punto en la lista.
  Future<void> guardarTodos({
    required String entrenamientoId,
    required List<PuntoGps> puntos,
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

  @override
  Future<void> guardarTodos({
    required String entrenamientoId,
    required List<PuntoGps> puntos,
  }) {
    return _cliente.from(tabla).insert(
          filasPara(entrenamientoId: entrenamientoId, puntos: puntos),
        );
  }

  /// Una fila por punto, con `orden_secuencia` = índice en la lista.
  static List<Map<String, Object>> filasPara({
    required String entrenamientoId,
    required List<PuntoGps> puntos,
  }) {
    return [
      for (var i = 0; i < puntos.length; i++)
        filaPara(
          entrenamientoId: entrenamientoId,
          punto: puntos[i],
          ordenSecuencia: i,
        ),
    ];
  }

  /// Fila con las columnas de `puntos_gps` (sin altitud, a propósito).
  static Map<String, Object> filaPara({
    required String entrenamientoId,
    required PuntoGps punto,
    required int ordenSecuencia,
  }) {
    return {
      'entrenamiento_id': entrenamientoId,
      'latitud': punto.latitud,
      'longitud': punto.longitud,
      'capturado_en': punto.capturadoEn.toUtc().toIso8601String(),
      'orden_secuencia': ordenSecuencia,
    };
  }
}
