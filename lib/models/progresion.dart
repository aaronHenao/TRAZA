import 'package:flutter/foundation.dart';

import 'nivel.dart';

/// Dónde está un corredor dentro de la progresión de niveles (SCRUM-178).
///
/// Solo lee y compara: la experiencia acumulada se la dan hecha —la calcula el
/// motor de experiencia al completar retos— y los umbrales vienen de los
/// niveles que registró el administrador (SCRUM-177). Aquí no se suma ni se
/// acredita XP; eso pertenece a esas historias.
///
/// Los cuatro datos que pide el criterio 1 salen de aquí: [nivelActual],
/// [experiencia], el umbral de [siguienteNivel] y [experienciaFaltante].
@immutable
class Progresion {
  const Progresion._({
    required this.experiencia,
    required this.nivelActual,
    required this.siguienteNivel,
  });

  /// Calcula en qué punto de [niveles] deja al corredor su [experiencia].
  ///
  /// [niveles] puede venir en cualquier orden: aquí se ordena por umbral antes
  /// de buscar, para no depender de cómo llegó la lista.
  factory Progresion.calcular({
    required int experiencia,
    required List<Nivel> niveles,
  }) {
    final ordenados = [...niveles]
      ..sort((a, b) => a.umbralExperiencia.compareTo(b.umbralExperiencia));

    Nivel? actual;
    Nivel? siguiente;
    for (final nivel in ordenados) {
      // Se entra al nivel al llegar a su umbral, no al pasarlo: con 100 XP
      // justos ya se es Bronce si Bronce empieza en 100.
      if (nivel.umbralExperiencia <= experiencia) {
        actual = nivel;
      } else {
        siguiente = nivel;
        break;
      }
    }

    return Progresion._(
      experiencia: experiencia,
      nivelActual: actual,
      siguienteNivel: siguiente,
    );
  }

  /// La experiencia acumulada del corredor, tal cual se la entregaron.
  final int experiencia;

  /// El nivel más alto ya alcanzado, o null si todavía no llega al primero.
  ///
  /// Que sea null no es un error: es el corredor que acaba de empezar y aún no
  /// ha alcanzado ningún nivel.
  final Nivel? nivelActual;

  /// El siguiente nivel por alcanzar, o null si no hay ninguno por encima.
  final Nivel? siguienteNivel;

  /// Si el administrador ya registró niveles.
  ///
  /// Sin niveles no hay progresión que mostrar, y eso se avisa con un mensaje,
  /// no con un error (criterio 4 de SCRUM-178).
  bool get hayNiveles => nivelActual != null || siguienteNivel != null;

  /// Si ya está en el nivel más alto que existe hoy.
  ///
  /// Distinto de [hayNiveles]: aquí sí alcanzó niveles, lo que no hay es uno
  /// por encima (criterio 3).
  bool get enNivelMaximo => nivelActual != null && siguienteNivel == null;

  /// Cuánta experiencia le falta para el siguiente nivel, o null si no hay
  /// siguiente.
  ///
  /// Nunca es negativa ni cero: si ya hubiera llegado a ese umbral, ese nivel
  /// sería el actual y no el siguiente.
  int? get experienciaFaltante => siguienteNivel == null
      ? null
      : siguienteNivel!.umbralExperiencia - experiencia;

  /// Desde qué experiencia cuenta el tramo que está recorriendo.
  ///
  /// Es el umbral del nivel actual, o cero mientras no haya alcanzado ninguno:
  /// el primer tramo se recorre desde el principio.
  int get inicioDelTramo => nivelActual?.umbralExperiencia ?? 0;

  /// Qué parte del tramo lleva recorrida, de 0 a 1, para poder dibujarlo
  /// (criterio 2 de SCRUM-178). Null si no hay siguiente nivel que alcanzar.
  double? get avance {
    final siguiente = siguienteNivel;
    if (siguiente == null) return null;

    final tramo = siguiente.umbralExperiencia - inicioDelTramo;
    // Dos niveles no pueden empezar en el mismo umbral (SCRUM-177), así que el
    // tramo siempre mide algo; la guarda evita una división por cero si algún
    // día esa regla cambiara.
    if (tramo <= 0) return 0;

    return ((experiencia - inicioDelTramo) / tramo).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is Progresion &&
      other.experiencia == experiencia &&
      other.nivelActual == nivelActual &&
      other.siguienteNivel == siguienteNivel;

  @override
  int get hashCode => Object.hash(experiencia, nivelActual, siguienteNivel);

  @override
  String toString() =>
      'Progresion($experiencia XP, actual: ${nivelActual?.nombre ?? 'ninguno'}, '
      'siguiente: ${siguienteNivel?.nombre ?? 'ninguno'})';
}
