import 'package:flutter/foundation.dart';

/// Situación en la que puede estar el cronómetro de un entrenamiento.
enum MarchaCronometro {
  /// Aún no se ha iniciado la actividad (o ya se detuvo).
  detenido,

  /// La actividad está en curso y el tiempo avanza.
  enCurso,

  /// La actividad está en pausa: el tiempo transcurrido se conserva
  /// pero no avanza.
  pausado,
}

/// Instantánea inmutable del cronómetro que consumen los widgets.
@immutable
class EstadoCronometro {
  const EstadoCronometro({
    required this.transcurrido,
    required this.marcha,
  });

  /// Estado inicial: el cronómetro arranca siempre desde cero.
  const EstadoCronometro.inicial()
      : transcurrido = Duration.zero,
        marcha = MarchaCronometro.detenido;

  /// Tiempo acumulado de la actividad, sin contar las pausas.
  final Duration transcurrido;

  final MarchaCronometro marcha;

  bool get estaEnCurso => marcha == MarchaCronometro.enCurso;

  bool get estaPausado => marcha == MarchaCronometro.pausado;

  /// Tiempo transcurrido en formato `HH:MM:SS`, tal como lo muestra
  /// el prototipo (`00:00:00`).
  String get tiempoFormateado => formatearTiempoEntrenamiento(transcurrido);

  EstadoCronometro copyWith({
    Duration? transcurrido,
    MarchaCronometro? marcha,
  }) {
    return EstadoCronometro(
      transcurrido: transcurrido ?? this.transcurrido,
      marcha: marcha ?? this.marcha,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EstadoCronometro &&
      other.transcurrido == transcurrido &&
      other.marcha == marcha;

  @override
  int get hashCode => Object.hash(transcurrido, marcha);

  @override
  String toString() => 'EstadoCronometro($tiempoFormateado, ${marcha.name})';
}

/// Formatea una duración como `HH:MM:SS` con dos dígitos por campo.
///
/// Las horas crecen más allá de 99 si hiciera falta y las duraciones
/// negativas se tratan como cero.
String formatearTiempoEntrenamiento(Duration duracion) {
  final totalSegundos = duracion.isNegative ? 0 : duracion.inSeconds;
  final horas = totalSegundos ~/ 3600;
  final minutos = (totalSegundos % 3600) ~/ 60;
  final segundos = totalSegundos % 60;

  String dosDigitos(int valor) => valor.toString().padLeft(2, '0');

  return '${dosDigitos(horas)}:${dosDigitos(minutos)}:${dosDigitos(segundos)}';
}
