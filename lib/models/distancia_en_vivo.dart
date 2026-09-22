import 'package:flutter/foundation.dart';

/// Distancia recorrida y ritmo de la actividad en curso (SCRUM-112).
///
/// Formatea igual que el resumen (`ResumenEntrenamiento`) para que lo que
/// el usuario ve mientras corre coincida con lo que ve al terminar.
@immutable
class DistanciaEnVivo {
  const DistanciaEnVivo({this.metros = 0, this.ritmoActual});

  /// Por debajo de esta distancia el ritmo no significa nada: con unos pocos
  /// metros de ruido del GPS saldrían ritmos de horas por kilómetro.
  static const distanciaMinimaParaRitmoMetros = 10.0;

  /// Lo que se muestra cuando todavía no hay ritmo que mostrar.
  static const sinRitmo = "0'00\"";

  /// Metros acumulados entre los puntos aceptados. Nunca negativo.
  final double metros;

  /// Tiempo por kilómetro al paso de los últimos segundos, o `null` si el
  /// usuario está quieto o acaba de arrancar (SCRUM-116).
  ///
  /// Es lo que se enseña en pantalla. El promedio de toda la actividad
  /// ([ritmoPara]) se guarda para el resumen: en vivo subía sin parar con
  /// el usuario detenido, porque el tiempo corría y la distancia no.
  final Duration? ritmoActual;

  /// Kilómetros con dos decimales, como el prototipo (`5.23 km`).
  String get kilometros => '${(metros / 1000).toStringAsFixed(2)} km';

  /// El ritmo actual ya formateado (`6'10"`), o `0'00"` si no hay.
  String get ritmoActualFormateado => ritmoActual == null
      ? sinRitmo
      : formatearRitmo(ritmoActual!);

  /// Ritmo **promedio** de toda la actividad para el tiempo
  /// [transcurrido]. Mientras no haya distancia suficiente, `0'00"`.
  ///
  /// No usar en vivo: con el usuario parado el tiempo sigue corriendo y
  /// este número crece indefinidamente. Para la pantalla está
  /// [ritmoActualFormateado].
  String ritmoPara(Duration transcurrido) {
    if (metros < distanciaMinimaParaRitmoMetros) return sinRitmo;
    // `inMilliseconds / metros` ya son segundos por kilómetro: dividir
    // milisegundos entre metros equivale a dividir segundos entre kilómetros.
    return formatearRitmo(
      Duration(milliseconds: (transcurrido.inMilliseconds / metros * 1000).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DistanciaEnVivo &&
      other.metros == metros &&
      other.ritmoActual == ritmoActual;

  @override
  int get hashCode => Object.hash(metros, ritmoActual);

  @override
  String toString() => 'DistanciaEnVivo($metros m, $ritmoActualFormateado)';
}

/// Minutos y segundos por kilómetro (`6'10"`).
///
/// Se redondea el total antes de separar minutos y segundos, para que
/// 5'59.9" quede en 6'00" y no en 5'60".
String formatearRitmo(Duration porKilometro) {
  final totalSegundos = porKilometro.isNegative
      ? 0
      : (porKilometro.inMilliseconds / 1000).round();
  final minutos = totalSegundos ~/ 60;
  final segundos = (totalSegundos % 60).toString().padLeft(2, '0');
  return "$minutos'$segundos\"";
}
