import 'package:flutter/foundation.dart';

import 'resumen_entrenamiento.dart';

/// Lo que el usuario lleva entrenado esta semana, para la portada.
///
/// La semana empieza el lunes, como el calendario local. Se arma con los
/// entrenamientos que ya tiene guardados y con el objetivo de distancia que
/// haya configurado en su perfil.
@immutable
class ResumenSemana {
  const ResumenSemana({
    required this.entrenamientos,
    required this.distanciaMetros,
    this.metaKilometros,
  });

  /// Cuántos entrenamientos terminó esta semana.
  final int entrenamientos;

  /// Lo que suma la distancia de todos ellos. Los entrenamientos sin
  /// distancia (los que no llegaron a registrar recorrido) suman cero.
  final double distanciaMetros;

  /// Objetivo semanal de distancia, si lo configuró. En kilómetros, como lo
  /// eligió en el perfil.
  final num? metaKilometros;

  bool get vacia => entrenamientos == 0;

  double get kilometros => distanciaMetros / 1000;

  /// Kilómetros con un decimal, como el prototipo (`18.4`).
  String get kilometrosTexto => kilometros.toStringAsFixed(1);

  /// Qué parte del objetivo lleva cumplida, entre 0 y 1, o null si no tiene
  /// objetivo de distancia.
  ///
  /// Se recorta en 1: pasarse de la meta llena la barra, no la desborda.
  double? get progreso {
    final meta = metaKilometros;
    if (meta == null || meta <= 0) return null;
    return (kilometros / meta).clamp(0.0, 1.0);
  }

  /// `9.2 / 15 km`, o solo los kilómetros si no hay objetivo.
  String get avanceTexto {
    final meta = metaKilometros;
    if (meta == null) return '$kilometrosTexto km';
    return '$kilometrosTexto / ${_sinCerosSobrantes(meta)} km';
  }

  /// Arma el resumen con los entrenamientos de la semana de [ahora].
  static ResumenSemana desde(
    List<ResumenEntrenamiento> historial, {
    required DateTime ahora,
    num? metaKilometros,
  }) {
    final desdeElLunes = inicioDeSemana(ahora);
    final deEstaSemana = historial.where(
      (entrenamiento) => !entrenamiento.fechaFin.toLocal().isBefore(
        desdeElLunes,
      ),
    );

    var metros = 0.0;
    var cuantos = 0;
    for (final entrenamiento in deEstaSemana) {
      cuantos++;
      metros += entrenamiento.distanciaMetros ?? 0;
    }

    return ResumenSemana(
      entrenamientos: cuantos,
      distanciaMetros: metros,
      metaKilometros: metaKilometros,
    );
  }

  /// El lunes de la semana de [ahora], a las 00:00 en hora local.
  static DateTime inicioDeSemana(DateTime ahora) {
    final hoy = ahora.toLocal();
    // `weekday` va de 1 (lunes) a 7 (domingo).
    final dia = DateTime(hoy.year, hoy.month, hoy.day);
    return dia.subtract(Duration(days: hoy.weekday - 1));
  }

  /// `15` en vez de `15.0`, pero `7.5` se mantiene.
  static String _sinCerosSobrantes(num valor) {
    final entero = valor.toInt();
    return valor == entero ? '$entero' : '$valor';
  }

  @override
  bool operator ==(Object other) =>
      other is ResumenSemana &&
      other.entrenamientos == entrenamientos &&
      other.distanciaMetros == distanciaMetros &&
      other.metaKilometros == metaKilometros;

  @override
  int get hashCode => Object.hash(entrenamientos, distanciaMetros, metaKilometros);

  @override
  String toString() =>
      'ResumenSemana($entrenamientos entrenamientos, $avanceTexto)';
}
