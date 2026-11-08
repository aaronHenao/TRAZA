import 'package:flutter/foundation.dart';

import 'ruta.dart';
import 'ruta_oficial.dart';

/// En qué va el corredor con cada ruta del mapa (rutas oficiales, etapa 2).
enum EstadoParada {
  /// Ya la corrió completa.
  completada,

  /// La primera, en el orden del camino, que le falta.
  siguiente,

  /// Le falta y viene después de la siguiente.
  bloqueada,
}

/// Una ruta oficial en el camino del mapa de progresión, con su estado para
/// el corredor (rutas oficiales, etapa 2).
@immutable
class ParadaMapa {
  const ParadaMapa({required this.oficial, required this.estado});

  final RutaOficial oficial;
  final EstadoParada estado;

  Ruta get ruta => oficial.ruta;

  @override
  bool operator ==(Object other) =>
      other is ParadaMapa && other.oficial == oficial && other.estado == estado;

  @override
  int get hashCode => Object.hash(oficial, estado);

  @override
  String toString() => 'ParadaMapa(${ruta.nombre}, ${estado.name})';
}

/// El camino de rutas oficiales del corredor y en qué punto de él va
/// (rutas oficiales, etapa 2; antes, el camino de niveles de SCRUM-226).
///
/// Se calcula a partir de qué rutas completó, no de una posición guardada:
/// si el administrador reordena o quita una ruta, el camino se rehace y nadie
/// pierde lo que ya corrió.
@immutable
class MapaProgresion {
  const MapaProgresion._({required this.paradas, required this.indiceActual});

  /// Ubica al corredor en el camino de [oficiales], que pueden llegar en
  /// cualquier orden. [completadas] son los ids de las rutas que completó;
  /// las que ya no son oficiales no cuentan.
  factory MapaProgresion.calcular({
    required List<RutaOficial> oficiales,
    required Set<String> completadas,
  }) {
    final ordenadas = [...oficiales]
      ..sort((a, b) => a.posicion.compareTo(b.posicion));

    // La siguiente es la primera que falta. Una completada después de ella
    // (fuera de orden) se marca, pero no mueve al corredor.
    final siguiente = ordenadas.indexWhere(
      (oficial) => !completadas.contains(oficial.ruta.id),
    );

    final paradas = [
      for (final (i, oficial) in ordenadas.indexed)
        ParadaMapa(
          oficial: oficial,
          estado: completadas.contains(oficial.ruta.id)
              ? EstadoParada.completada
              : (i == siguiente
                    ? EstadoParada.siguiente
                    : EstadoParada.bloqueada),
        ),
    ];

    return MapaProgresion._(
      paradas: List.unmodifiable(paradas),
      // Sin siguiente, las completó todas: el corredor queda en la última.
      indiceActual: paradas.isEmpty
          ? null
          : (siguiente < 0 ? paradas.length - 1 : siguiente),
    );
  }

  /// Las rutas oficiales en el orden del camino.
  final List<ParadaMapa> paradas;

  /// Dónde va el corredor: la siguiente; si las completó todas, la última.
  /// Null si no hay rutas oficiales.
  final int? indiceActual;

  bool get hayRutas => paradas.isNotEmpty;

  int get totalCompletadas => paradas
      .where((parada) => parada.estado == EstadoParada.completada)
      .length;

  ParadaMapa? get siguiente {
    for (final parada in paradas) {
      if (parada.estado == EstadoParada.siguiente) return parada;
    }
    return null;
  }

  bool get caminoTerminado => hayRutas && siguiente == null;

  @override
  bool operator ==(Object other) =>
      other is MapaProgresion &&
      listEquals(other.paradas, paradas) &&
      other.indiceActual == indiceActual;

  @override
  int get hashCode => Object.hash(Object.hashAll(paradas), indiceActual);

  @override
  String toString() =>
      'MapaProgresion($totalCompletadas de ${paradas.length} completadas, '
      'actual $indiceActual)';
}
