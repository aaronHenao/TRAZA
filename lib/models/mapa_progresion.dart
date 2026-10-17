import 'package:flutter/foundation.dart';

import 'nivel.dart';
import 'progresion.dart';

/// Un punto del camino del mapa de progresión (SCRUM-226): el inicio o uno de
/// los niveles que registró el administrador.
@immutable
class ParadaMapa {
  const ParadaMapa({
    required this.nombre,
    required this.umbralExperiencia,
    required this.alcanzada,
    this.nivelId,
  });

  /// Null en la parada inicial, que no es un nivel.
  final String? nivelId;
  final String nombre;
  final int umbralExperiencia;
  final bool alcanzada;

  bool get esInicio => nivelId == null;

  @override
  bool operator ==(Object other) =>
      other is ParadaMapa &&
      other.nivelId == nivelId &&
      other.nombre == nombre &&
      other.umbralExperiencia == umbralExperiencia &&
      other.alcanzada == alcanzada;

  @override
  int get hashCode =>
      Object.hash(nivelId, nombre, umbralExperiencia, alcanzada);

  @override
  String toString() =>
      'ParadaMapa($nombre, $umbralExperiencia XP'
      '${alcanzada ? ', alcanzada' : ''})';
}

/// El camino de niveles del corredor y en qué punto de él está (SCRUM-226).
///
/// Solo ordena y ubica: dónde termina cada tramo y cuánto lleva recorrido lo
/// sabe ya [Progresion] (SCRUM-178), así que se apoya en ella en vez de
/// repetir la cuenta.
@immutable
class MapaProgresion {
  const MapaProgresion._({
    required this.experiencia,
    required this.paradas,
    required this.indiceActual,
    required this.avanceEnTramo,
  });

  /// Ubica a quien tiene [experiencia] en el camino de [niveles], que pueden
  /// llegar en cualquier orden.
  factory MapaProgresion.calcular({
    required int experiencia,
    required List<Nivel> niveles,
  }) {
    final ordenados = [...niveles]
      ..sort((a, b) => a.umbralExperiencia.compareTo(b.umbralExperiencia));
    final progresion = Progresion.calcular(
      experiencia: experiencia,
      niveles: ordenados,
    );

    // La regla de cuándo se alcanza un nivel vive en Progresion: aquí solo
    // se busca en qué parada quedó (0 = el inicio, antes del primer nivel).
    final actual = progresion.nivelActual;
    final indiceActual = actual == null
        ? 0
        : ordenados.indexWhere((nivel) => nivel.id == actual.id) + 1;

    final paradas = [
      // El punto de partida: ahí está quien todavía no ha avanzado
      // (criterio 2), y es el único si no hay niveles.
      const ParadaMapa(nombre: 'Inicio', umbralExperiencia: 0, alcanzada: true),
      for (final (i, nivel) in ordenados.indexed)
        ParadaMapa(
          nivelId: nivel.id,
          nombre: nivel.nombre,
          umbralExperiencia: nivel.umbralExperiencia,
          alcanzada: i + 1 <= indiceActual,
        ),
    ];

    return MapaProgresion._(
      experiencia: experiencia,
      paradas: List.unmodifiable(paradas),
      indiceActual: indiceActual,
      avanceEnTramo: progresion.avance,
    );
  }

  final int experiencia;

  /// La parada inicial seguida de los niveles, de menor a mayor umbral.
  final List<ParadaMapa> paradas;

  /// Índice en [paradas] de la última alcanzada: 0 es el punto inicial.
  final int indiceActual;

  /// Qué parte del tramo hacia la siguiente parada lleva, de 0 a 1. Null si
  /// no hay siguiente: nivel máximo o sin niveles.
  final double? avanceEnTramo;

  bool get hayNiveles => paradas.length > 1;

  bool get enUltimaParada => indiceActual == paradas.length - 1;

  @override
  bool operator ==(Object other) =>
      other is MapaProgresion &&
      other.experiencia == experiencia &&
      listEquals(other.paradas, paradas) &&
      other.indiceActual == indiceActual &&
      other.avanceEnTramo == avanceEnTramo;

  @override
  int get hashCode => Object.hash(
    experiencia,
    Object.hashAll(paradas),
    indiceActual,
    avanceEnTramo,
  );

  @override
  String toString() =>
      'MapaProgresion($experiencia XP, parada $indiceActual de '
      '${paradas.length}, avance $avanceEnTramo)';
}
