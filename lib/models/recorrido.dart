import 'package:flutter/foundation.dart';

import 'punto_gps.dart';

/// En qué va la sincronización del recorrido con Supabase.
enum EstadoSincronizacion {
  /// La actividad sigue; los puntos solo están en local.
  pendiente,

  /// Se está enviando el lote.
  enCurso,

  /// Todos los puntos quedaron en `puntos_gps`.
  completada,

  /// El envío falló; los puntos siguen en local.
  fallida,
}

/// Puntos registrados en la actividad en curso, en orden de captura.
///
/// Se acumulan en local mientras dura la actividad y se sincronizan de
/// una vez al finalizar. `puntos[i]` se guarda con `orden_secuencia = i`.
@immutable
class Recorrido {
  const Recorrido({
    this.puntos = const [],
    this.sincronizacion = EstadoSincronizacion.pendiente,
  });

  final List<PuntoGps> puntos;
  final EstadoSincronizacion sincronizacion;

  PuntoGps? get ultimo => puntos.isEmpty ? null : puntos.last;

  Recorrido copyWith({
    List<PuntoGps>? puntos,
    EstadoSincronizacion? sincronizacion,
  }) {
    return Recorrido(
      puntos: puntos ?? this.puntos,
      sincronizacion: sincronizacion ?? this.sincronizacion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Recorrido &&
      listEquals(other.puntos, puntos) &&
      other.sincronizacion == sincronizacion;

  @override
  int get hashCode => Object.hash(Object.hashAll(puntos), sincronizacion);

  @override
  String toString() =>
      'Recorrido(${puntos.length} puntos, ${sincronizacion.name})';
}
