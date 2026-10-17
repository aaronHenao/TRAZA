import 'package:flutter/foundation.dart';

import 'punto_gps.dart';
import 'tramos.dart';

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
///
/// Lo recorrido entre dos pausas es un tramo ([tramos]). El trazo se dibuja
/// por tramos para no unir con una recta el punto donde se pausó con el
/// punto donde se reanudó (BUG-005).
@immutable
class Recorrido {
  const Recorrido({
    this.puntos = const [],
    this.cortes = const [],
    this.sincronizacion = EstadoSincronizacion.pendiente,
  });

  final List<PuntoGps> puntos;

  /// Índices de [puntos] donde empieza un tramo nuevo (el primer punto
  /// tras reanudar), en orden creciente. El primer tramo empieza en 0 y no
  /// aparece aquí.
  final List<int> cortes;

  final EstadoSincronizacion sincronizacion;

  PuntoGps? get ultimo => puntos.isEmpty ? null : puntos.last;

  /// [puntos] separados por las pausas, cada tramo en orden de captura.
  List<List<PuntoGps>> get tramos => dividirEnTramos(puntos, cortes);

  Recorrido copyWith({
    List<PuntoGps>? puntos,
    List<int>? cortes,
    EstadoSincronizacion? sincronizacion,
  }) {
    return Recorrido(
      puntos: puntos ?? this.puntos,
      cortes: cortes ?? this.cortes,
      sincronizacion: sincronizacion ?? this.sincronizacion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Recorrido &&
      listEquals(other.puntos, puntos) &&
      listEquals(other.cortes, cortes) &&
      other.sincronizacion == sincronizacion;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(puntos),
    Object.hashAll(cortes),
    sincronizacion,
  );

  @override
  String toString() =>
      'Recorrido(${puntos.length} puntos, ${tramos.length} tramos, '
      '${sincronizacion.name})';
}
