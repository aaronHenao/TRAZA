import 'package:flutter/foundation.dart';

import 'estado_cronometro.dart';
import 'punto_gps.dart';

/// Lo que muestra el resumen de un entrenamiento recién finalizado
/// (`screen-summary`, SCRUM-117).
@immutable
class ResumenEntrenamiento {
  const ResumenEntrenamiento({
    required this.entrenamientoId,
    required this.nombreActividad,
    required this.fechaFin,
    required this.duracion,
    this.distanciaMetros,
    this.puntos = const [],
  });

  /// Lo que se muestra cuando un dato todavía no existe, por ejemplo la
  /// distancia mientras no se calcule (SCRUM-111 y SCRUM-112).
  static const sinDato = '—';

  /// Por debajo de esta distancia el ritmo no significa nada: con unos pocos
  /// metros de ruido del GPS saldrían ritmos de horas por kilómetro.
  static const distanciaMinimaParaRitmoMetros = 10.0;

  /// `id` de la fila de `entrenamientos` de esta sesión, o null si se entrenó
  /// sin sesión y no hay fila (hasta que exista SCRUM-99).
  final String? entrenamientoId;

  final String nombreActividad;
  final DateTime fechaFin;

  /// Tiempo de la actividad sin contar las pausas, como lo dio el cronómetro.
  final Duration duracion;

  /// null mientras la distancia no se calcule (SCRUM-111 y SCRUM-112).
  final double? distanciaMetros;

  /// Puntos GPS del recorrido, en orden de captura. Los dibuja SCRUM-120.
  final List<PuntoGps> puntos;

  /// Si este es el resumen del entrenamiento [entrenamientoId] que pide la
  /// navegación (SCRUM-122). Sin sesión ambos son null y también coinciden.
  bool correspondeA(String? entrenamientoId) =>
      this.entrenamientoId == entrenamientoId;

  /// `HH:MM:SS`, igual que el cronómetro de la actividad.
  String get tiempo => formatearTiempoEntrenamiento(duracion);

  /// Kilómetros con dos decimales, como el prototipo (`5.23 km`).
  String get distancia {
    final metros = distanciaMetros;
    if (metros == null) return sinDato;
    return '${(metros / 1000).toStringAsFixed(2)} km';
  }

  /// Minutos y segundos por kilómetro, como el prototipo (`6'10"/km`).
  String get ritmo {
    final metros = distanciaMetros;
    if (metros == null || metros < distanciaMinimaParaRitmoMetros) {
      return sinDato;
    }
    // Se redondea el total antes de separar minutos y segundos, para que
    // 5'59.9" quede en 6'00" y no en 5'60".
    final segundosPorKm = (duracion.inMilliseconds / metros).round();
    final minutos = segundosPorKm ~/ 60;
    final segundos = (segundosPorKm % 60).toString().padLeft(2, '0');
    return "$minutos'$segundos\"/km";
  }

  /// Actividad y cuándo terminó, como el prototipo (`Correr · hoy`).
  String subtitulo(DateTime ahora) => '$nombreActividad · ${_cuando(ahora)}';

  String _cuando(DateTime ahora) {
    final fin = fechaFin.toLocal();
    final hoy = ahora.toLocal();
    // Días de calendario, en UTC para que un cambio de horario no convierta
    // un día en 23 horas.
    final dias = DateTime.utc(
      hoy.year,
      hoy.month,
      hoy.day,
    ).difference(DateTime.utc(fin.year, fin.month, fin.day)).inDays;

    if (dias == 0) return 'hoy';
    if (dias == 1) return 'ayer';
    final fecha = '${fin.day} ${_meses[fin.month - 1]}';
    return fin.year == hoy.year ? fecha : '$fecha ${fin.year}';
  }

  static const _meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
}
