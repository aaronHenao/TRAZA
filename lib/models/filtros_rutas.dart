import 'package:flutter/foundation.dart';

import 'dificultad.dart';
import 'rango_distancia.dart';
import 'ruta.dart';

/// Lo elegido para filtrar las rutas de Explorar rutas: la dificultad
/// (HU-36) y el rango de distancia (HU-37).
///
/// Una ruta tiene que cumplir todo lo elegido a la vez (SCRUM-275, criterio
/// 3 de HU-37): una fácil de 15 km no sale entre las fáciles de 5 a 10 km.
/// Sin nada elegido pasan todas.
///
/// Se filtra en la app, sobre la lista que ya llegó —las cercanas, las
/// recientes o lo que encontró una búsqueda—, así que cambiar un filtro no
/// vuelve a consultar: el cambio se ve al instante, y quitarlo devuelve la
/// lista tal como estaba (criterio 4). Cada lista trae un máximo de rutas
/// (`SupabaseRutasRepository.limite`), y el filtro trabaja sobre esas.
@immutable
class FiltrosRutas {
  const FiltrosRutas({this.dificultad, this.distancia});

  final Dificultad? dificultad;
  final RangoDistancia? distancia;

  /// Si no hay nada elegido.
  bool get ninguno => dificultad == null && distancia == null;

  /// Cuántos filtros hay elegidos.
  int get cuantos => [dificultad, distancia].nonNulls.length;

  /// Si [ruta] cumple todo lo elegido. Una ruta sin clasificar no cumple
  /// ninguna dificultad, y una sin distancia registrada, ningún rango: no se
  /// sabe cómo es.
  bool admite(Ruta ruta) =>
      (dificultad == null || ruta.dificultad == dificultad) &&
      (distancia?.contiene(ruta.distanciaKm) ?? true);

  /// Las de [rutas] que cumplen todo, en el mismo orden. Sin nada elegido,
  /// la misma lista.
  List<Ruta> aplicar(List<Ruta> rutas) => ninguno
      ? rutas
      : [
          for (final ruta in rutas)
            if (admite(ruta)) ruta,
        ];

  @override
  bool operator ==(Object other) =>
      other is FiltrosRutas &&
      other.dificultad == dificultad &&
      other.distancia == distancia;

  @override
  int get hashCode => Object.hash(dificultad, distancia);

  @override
  String toString() => 'FiltrosRutas(${dificultad?.name}, ${distancia?.name})';
}
