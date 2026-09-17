import 'package:flutter/foundation.dart';

/// Distancia recorrida en la actividad en curso (SCRUM-112).
///
/// Formatea igual que el resumen (`ResumenEntrenamiento`) para que lo que
/// el usuario ve mientras corre coincida con lo que ve al terminar.
@immutable
class DistanciaEnVivo {
  const DistanciaEnVivo({this.metros = 0});

  /// Por debajo de esta distancia el ritmo no significa nada: con unos pocos
  /// metros de ruido del GPS saldrían ritmos de horas por kilómetro.
  static const distanciaMinimaParaRitmoMetros = 10.0;

  /// Metros acumulados entre los puntos aceptados. Nunca negativo.
  final double metros;

  /// Kilómetros con dos decimales, como el prototipo (`5.23 km`).
  String get kilometros => '${(metros / 1000).toStringAsFixed(2)} km';

  /// Minutos y segundos por kilómetro (`6'10"`) para el tiempo
  /// [transcurrido]. Mientras no haya distancia suficiente, `0'00"`.
  String ritmoPara(Duration transcurrido) {
    if (metros < distanciaMinimaParaRitmoMetros) return "0'00\"";
    // Se redondea el total antes de separar minutos y segundos, para que
    // 5'59.9" quede en 6'00" y no en 5'60".
    final segundosPorKm = (transcurrido.inMilliseconds / metros).round();
    final minutos = segundosPorKm ~/ 60;
    final segundos = (segundosPorKm % 60).toString().padLeft(2, '0');
    return "$minutos'$segundos\"";
  }

  @override
  bool operator ==(Object other) =>
      other is DistanciaEnVivo && other.metros == metros;

  @override
  int get hashCode => metros.hashCode;

  @override
  String toString() => 'DistanciaEnVivo($metros m)';
}
