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

  /// Lo que se muestra cuando no hay ritmo que mostrar.
  static const sinRitmo = "0'00\"";

  /// Metros acumulados entre los puntos aceptados. Nunca negativo.
  final double metros;

  /// Tiempo por kilómetro al paso de los últimos segundos, o `null` si el
  /// usuario está quieto o todavía no hay lecturas (SCRUM-116).
  ///
  /// Es lo que se enseña en pantalla. [ritmoPara] es el promedio de toda la
  /// actividad, para el resumen: en vivo subía sin techo con el usuario
  /// parado, porque el tiempo corría y la distancia no.
  final Duration? ritmoActual;

  /// Kilómetros con dos decimales, como el prototipo (`5.23 km`).
  String get kilometros => '${(metros / 1000).toStringAsFixed(2)} km';

  /// El ritmo actual ya formateado (`6'10"`), o `0'00"` si no hay.
  String get ritmoActualFormateado {
    final ritmo = ritmoActual;
    if (ritmo == null) return sinRitmo;
    final segundosPorKm = (ritmo.inMilliseconds / 1000).round();
    return _formatear(segundosPorKm);
  }

  /// Minutos y segundos por kilómetro (`6'10"`) para el tiempo
  /// [transcurrido]. Mientras no haya distancia suficiente, `0'00"`.
  String ritmoPara(Duration transcurrido) {
    if (metros < distanciaMinimaParaRitmoMetros) return sinRitmo;
    return _formatear((transcurrido.inMilliseconds / metros).round());
  }

  /// Se redondea el total antes de separar minutos y segundos, para que
  /// 5'59.9" quede en 6'00" y no en 5'60".
  static String _formatear(int segundosPorKm) {
    final minutos = segundosPorKm ~/ 60;
    final segundos = (segundosPorKm % 60).toString().padLeft(2, '0');
    return "$minutos'$segundos\"";
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
