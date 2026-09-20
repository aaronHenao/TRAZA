import 'package:flutter/foundation.dart';

import 'distancia_en_vivo.dart';
import 'estado_cronometro.dart';
import 'punto_gps.dart';

/// Lo que muestra el resumen de un entrenamiento recién finalizado
/// (`screen-summary`, SCRUM-117): tiempo total, distancia total, ritmo y los
/// puntos del trazado (SCRUM-119).
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

  /// Lo que se muestra cuando un dato no existe, por ejemplo la distancia de
  /// un entrenamiento que se guardó sin ella.
  static const sinDato = '—';

  /// `id` de la fila de `entrenamientos` de esta sesión, o null si se entrenó
  /// sin sesión y no hay fila (hasta que exista SCRUM-99).
  final String? entrenamientoId;

  final String nombreActividad;
  final DateTime fechaFin;

  /// Tiempo de la actividad sin contar las pausas, como lo dio el cronómetro.
  final Duration duracion;

  /// La que se calculó durante la actividad (SCRUM-111 y SCRUM-112), o null
  /// si el entrenamiento se guardó sin ella.
  final double? distanciaMetros;

  /// Puntos GPS del recorrido, en orden de captura. Con ellos se dibuja el
  /// trazado (SCRUM-119).
  final List<PuntoGps> puntos;

  /// Si este es el resumen del entrenamiento [entrenamientoId] que pide la
  /// navegación (SCRUM-122). Sin sesión ambos son null y también coinciden.
  bool correspondeA(String? entrenamientoId) =>
      this.entrenamientoId == entrenamientoId;

  /// `HH:MM:SS`, igual que el cronómetro de la actividad.
  String get tiempo => formatearTiempoEntrenamiento(duracion);

  // La distancia y el ritmo usan el mismo formato que la pantalla de la
  // actividad en curso (DistanciaEnVivo, SCRUM-114), para que lo que el
  // usuario ve al terminar coincida con lo que vio mientras entrenaba.

  /// Kilómetros con dos decimales, como el prototipo (`5.23 km`).
  String get distancia {
    final metros = distanciaMetros;
    if (metros == null) return sinDato;
    return DistanciaEnVivo(metros: metros).kilometros;
  }

  /// Minutos y segundos por kilómetro, como el prototipo (`6'10"/km`).
  ///
  /// Con muy poca distancia, la actividad en curso muestra `0'00"`; el
  /// resumen prefiere decir que no hay dato.
  String get ritmo {
    final metros = distanciaMetros;
    if (metros == null ||
        metros < DistanciaEnVivo.distanciaMinimaParaRitmoMetros) {
      return sinDato;
    }
    return '${DistanciaEnVivo(metros: metros).ritmoPara(duracion)}/km';
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
