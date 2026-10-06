/// Si los km de un entrenamiento contaron para los retos, y si no, por qué.
///
/// Se guarda en `experiencia_ganada.ajuste`, en la fila de 'actividad'.
enum AjusteExperiencia {
  /// Contó toda la distancia.
  ninguno,

  /// Sin distancia o sin duración no hay con qué validar.
  sinDatos,

  /// Promedio por encima de lo que se puede correr: va en carro o en bici.
  velocidadImposible,

  /// Solo en entrenamientos anteriores a `0018_xp_solo_por_retos.sql`, cuando
  /// la actividad daba XP: menos de 1 km no la daba.
  menosDelMinimo,

  /// Solo en entrenamientos anteriores a `0018_xp_solo_por_retos.sql`: llegó
  /// al tope diario de XP de actividad.
  topeDiario,
}

/// Reglas de XP (SCRUM-202).
///
/// El entrenamiento libre no da XP: la única forma de ganarla es completar
/// retos, y cada uno paga la XP que le puso el administrador. Lo que decide
/// esta regla es si los km de un entrenamiento cuentan para los retos activos
/// del mismo tipo de actividad.
///
/// La XP de actividad que se ganó antes de este cambio se conserva, así que
/// un entrenamiento viejo puede traer XP propia.
///
/// ⚠️ Quien aplica la regla es el servidor: la función de
/// `supabase/migrations/0018_xp_solo_por_retos.sql`. Esta copia existe para
/// probarla y para que la app explique el resultado. Si cambia una constante,
/// cambia en los dos lados.
abstract final class ReglaExperiencia {
  /// Un promedio por encima de esto no es alguien corriendo.
  static const velocidadMaximaKmH = 25.0;

  /// Si los km de un entrenamiento finalizado cuentan para los retos.
  static AjusteExperiencia evaluar({
    required double? distanciaMetros,
    required Duration? duracion,
  }) {
    if (distanciaMetros == null ||
        distanciaMetros <= 0 ||
        duracion == null ||
        duracion <= Duration.zero) {
      return AjusteExperiencia.sinDatos;
    }

    // km/h = metros × 3600 / ms. Se compara sin dividir: justo en el límite,
    // la división en coma flotante puede caer a cualquiera de los dos lados.
    if (distanciaMetros * 3600 > velocidadMaximaKmH * duracion.inMilliseconds) {
      return AjusteExperiencia.velocidadImposible;
    }

    return AjusteExperiencia.ninguno;
  }
}
