import 'package:flutter/foundation.dart';

import 'nivel.dart';

/// Los niveles que el usuario cruzó con la XP de un registro (SCRUM-197).
///
/// El nivel no se guarda: se deriva de la XP y de los umbrales (SCRUM-178).
/// Subir es automático por construcción; esto solo detecta que pasó, para
/// anunciarlo (SCRUM-199).
@immutable
class Ascenso {
  const Ascenso._(this.niveles);

  /// Los niveles cruzados entre [xpAntes] y [xpDespues], o null si no cruzó
  /// ninguno.
  ///
  /// Un nivel se cruza si su umbral queda por encima de [xpAntes] y a lo sumo
  /// en [xpDespues]: con la XP exacta ya se sube (criterio 1), y la de sobra
  /// no cambia qué nivel se alcanzó (criterio 2). Un reto grande puede cruzar
  /// varios de una vez (criterio 3). Sin llegar al siguiente umbral
  /// (SCRUM-200) o ya en el último nivel (criterio 6) no hay ascenso.
  static Ascenso? entre({
    required int xpAntes,
    required int xpDespues,
    required List<Nivel> niveles,
  }) {
    final cruzados =
        niveles
            .where(
              (nivel) =>
                  nivel.umbralExperiencia > xpAntes &&
                  nivel.umbralExperiencia <= xpDespues,
            )
            .toList()
          ..sort((a, b) => a.umbralExperiencia.compareTo(b.umbralExperiencia));

    return cruzados.isEmpty ? null : Ascenso._(List.unmodifiable(cruzados));
  }

  /// Los niveles cruzados, del umbral más bajo al más alto. Nunca vacía.
  final List<Nivel> niveles;

  /// El nivel en el que quedó: el más alto que alcanzó.
  Nivel get nivelFinal => niveles.last;

  @override
  bool operator ==(Object other) =>
      other is Ascenso && listEquals(other.niveles, niveles);

  @override
  int get hashCode => Object.hashAll(niveles);

  @override
  String toString() =>
      'Ascenso(${niveles.map((nivel) => nivel.nombre).join(' → ')})';
}
