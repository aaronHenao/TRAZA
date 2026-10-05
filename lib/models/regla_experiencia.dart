import 'package:flutter/foundation.dart';

/// Por qué una actividad dio menos XP de la que daría su distancia completa.
enum AjusteExperiencia {
  /// Contó toda la distancia.
  ninguno,

  /// Sin distancia o sin duración no hay con qué calcular ni validar.
  sinDatos,

  /// Promedio por encima de lo que se puede correr: va en carro o en bici.
  velocidadImposible,

  /// Menos del mínimo: abrir y cerrar la actividad no da XP.
  menosDelMinimo,

  /// Llegó al tope del día. Si ya estaba lleno, cuenta cero metros.
  topeDiario,
}

/// La XP que da una actividad finalizada y cómo se llegó a ella.
@immutable
class ExperienciaActividad {
  const ExperienciaActividad({
    required this.xp,
    required this.metrosContados,
    required this.ajuste,
  });

  final int xp;

  /// Los metros que entraron al cálculo. Se suman al tope del día, así que
  /// una actividad que no dio XP cuenta cero.
  final double metrosContados;

  final AjusteExperiencia ajuste;

  @override
  bool operator ==(Object other) =>
      other is ExperienciaActividad &&
      other.xp == xp &&
      other.metrosContados == metrosContados &&
      other.ajuste == ajuste;

  @override
  int get hashCode => Object.hash(xp, metrosContados, ajuste);

  @override
  String toString() =>
      'ExperienciaActividad($xp XP, $metrosContados m, ${ajuste.name})';
}

/// Reglas de XP por actividad (SCRUM-202).
///
/// Moverse siempre suma algo, pero poco: la mayor parte de la XP sale de
/// completar retos. El tope diario evita que se acumule XP a la fuerza y acota
/// lo que se gana con una distancia falseada, que la manda el cliente.
///
/// ⚠️ Quien asigna la XP es el servidor: la función de
/// `supabase/migrations/0009_experiencia.sql` aplica estas mismas reglas.
/// Esta copia existe para probarlas y para que la app explique el resultado.
/// Si cambia una constante, cambia en los dos lados.
abstract final class ReglaExperiencia {
  /// 5 XP por km: 1 XP por cada 200 m completos.
  static const metrosPorXp = 200;

  static const distanciaMinimaMetros = 1000.0;

  /// 25 km al día cuentan para XP. Alto a propósito: una tirada larga de un
  /// corredor capaz no debería quedar recortada.
  static const topeDiarioMetros = 25000.0;

  /// Lo máximo que da la actividad en un día: 125 XP.
  static int get topeDiarioXp => topeDiarioMetros ~/ metrosPorXp;

  /// Un promedio por encima de esto no es alguien corriendo.
  static const velocidadMaximaKmH = 25.0;

  /// Calcula la XP de una actividad.
  ///
  /// [metrosContadosHoy] son los metros que ya contaron para XP ese mismo día
  /// en otras actividades. Qué es "ese día" lo decide el servidor (hora de
  /// Colombia).
  static ExperienciaActividad calcular({
    required double? distanciaMetros,
    required Duration? duracion,
    double metrosContadosHoy = 0,
  }) {
    assert(metrosContadosHoy >= 0, 'Los metros del día no son negativos');

    if (distanciaMetros == null ||
        distanciaMetros <= 0 ||
        duracion == null ||
        duracion <= Duration.zero) {
      return _sinXp(AjusteExperiencia.sinDatos);
    }

    // km/h = metros × 3600 / ms. Se compara sin dividir: justo en el límite,
    // la división en coma flotante puede caer a cualquiera de los dos lados.
    if (distanciaMetros * 3600 > velocidadMaximaKmH * duracion.inMilliseconds) {
      return _sinXp(AjusteExperiencia.velocidadImposible);
    }

    if (distanciaMetros < distanciaMinimaMetros) {
      return _sinXp(AjusteExperiencia.menosDelMinimo);
    }

    final disponible = topeDiarioMetros - metrosContadosHoy;
    if (disponible <= 0) return _sinXp(AjusteExperiencia.topeDiario);

    final recortada = distanciaMetros > disponible;
    final metros = recortada ? disponible : distanciaMetros;
    return ExperienciaActividad(
      xp: metros ~/ metrosPorXp,
      metrosContados: metros,
      ajuste: recortada
          ? AjusteExperiencia.topeDiario
          : AjusteExperiencia.ninguno,
    );
  }

  static ExperienciaActividad _sinXp(AjusteExperiencia ajuste) =>
      ExperienciaActividad(xp: 0, metrosContados: 0, ajuste: ajuste);
}
