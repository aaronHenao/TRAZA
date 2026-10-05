import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Lo que pide el rol Runner Experto (SCRUM-210).
///
/// Vive en código y no en una tabla: por ahora los requisitos son fijos y la
/// app solo los muestra. Cuando el rol se pueda obtener, la base tendrá que
/// comprobarlos por su cuenta: con la publishable key cualquiera habla con
/// Postgres, así que lo que solo esté en Dart no está validado.
abstract final class RequisitosRunnerExperto {
  /// Experiencia acumulada que hay que tener.
  static const experiencia = 150000;

  /// Meses que tiene que tener la cuenta, contados desde que se creó.
  static const mesesDeAntiguedad = 6;
}

/// Lo que gana quien llega a Runner Experto (SCRUM-213).
enum VentajaRunnerExperto {
  evaluarRutas(
    titulo: 'Evaluar y clasificar rutas',
    detalle:
        'Califica las rutas que sugieren el administrador y la comunidad, y '
        'ayuda a ordenarlas para los demás.',
  ),
  insignia(
    titulo: 'Insignia de Runner Experto',
    detalle: 'Una insignia que te destaca frente al resto de corredores.',
  );

  const VentajaRunnerExperto({required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;
}

/// Dónde está el corredor frente a los requisitos de Runner Experto
/// (SCRUM-211, SCRUM-214).
///
/// Solo compara: la experiencia la acredita el motor de XP (SCRUM-192) y la
/// fecha de registro es la de la cuenta. No otorga el rol; que cumpla los
/// requisitos es [desbloqueado], nada más.
@immutable
class EstadoRunnerExperto {
  const EstadoRunnerExperto._({
    required this.experiencia,
    required this.fechaRegistro,
    required this.cumpleAntiguedadEl,
    required this.diasFaltantes,
    required this.avanceAntiguedad,
  });

  /// Ubica [experiencia] y [fechaRegistro] frente a los requisitos, visto
  /// desde [ahora].
  ///
  /// La antigüedad se cuenta en días del calendario, no en horas: quien se
  /// registró el 15 de marzo cumple seis meses el 15 de septiembre, a
  /// cualquier hora. Si ese día no existe (31 de agosto más seis meses), se
  /// toma el último del mes.
  factory EstadoRunnerExperto.calcular({
    required int experiencia,
    required DateTime fechaRegistro,
    required DateTime ahora,
  }) {
    final registro = _soloFecha(fechaRegistro);
    final hoy = _soloFecha(ahora);
    final cumpleEl = _sumarMeses(
      registro,
      RequisitosRunnerExperto.mesesDeAntiguedad,
    );

    final total = _diasEntre(registro, cumpleEl);
    final transcurridos = _diasEntre(registro, hoy);

    return EstadoRunnerExperto._(
      experiencia: experiencia,
      fechaRegistro: registro,
      cumpleAntiguedadEl: cumpleEl,
      diasFaltantes: math.max(0, _diasEntre(hoy, cumpleEl)),
      avanceAntiguedad: (transcurridos / total).clamp(0.0, 1.0),
    );
  }

  /// La experiencia acumulada, tal cual se la entregaron.
  final int experiencia;

  /// El día en que se creó la cuenta.
  final DateTime fechaRegistro;

  /// El día desde el que cumple la antigüedad.
  final DateTime cumpleAntiguedadEl;

  /// Días que faltan para cumplir la antigüedad. Cero si ya la cumple.
  final int diasFaltantes;

  /// Qué parte de la antigüedad lleva, de 0 a 1.
  final double avanceAntiguedad;

  bool get cumpleExperiencia =>
      experiencia >= RequisitosRunnerExperto.experiencia;

  bool get cumpleAntiguedad => diasFaltantes == 0;

  /// Si cumple los dos requisitos (criterio 3 de SCRUM-195).
  bool get desbloqueado => cumpleExperiencia && cumpleAntiguedad;

  /// XP que le falta. Cero si ya la tiene: la de sobra no cuenta.
  int get experienciaFaltante =>
      math.max(0, RequisitosRunnerExperto.experiencia - experiencia);

  /// Qué parte de la XP lleva, de 0 a 1.
  double get avanceExperiencia =>
      (experiencia / RequisitosRunnerExperto.experiencia).clamp(0.0, 1.0);

  static DateTime _soloFecha(DateTime momento) =>
      DateTime(momento.year, momento.month, momento.day);

  static DateTime _sumarMeses(DateTime fecha, int meses) {
    // Día 0 del mes siguiente es el último de este; el mes 13 rueda al año
    // siguiente sin ayuda.
    final ultimoDia = DateTime(fecha.year, fecha.month + meses + 1, 0).day;
    return DateTime(
      fecha.year,
      fecha.month + meses,
      math.min(fecha.day, ultimoDia),
    );
  }

  // En UTC para que un cambio de hora no haga de un día 23 o 25 horas.
  static int _diasEntre(DateTime desde, DateTime hasta) => DateTime.utc(
    hasta.year,
    hasta.month,
    hasta.day,
  ).difference(DateTime.utc(desde.year, desde.month, desde.day)).inDays;

  @override
  bool operator ==(Object other) =>
      other is EstadoRunnerExperto &&
      other.experiencia == experiencia &&
      other.fechaRegistro == fechaRegistro &&
      other.cumpleAntiguedadEl == cumpleAntiguedadEl &&
      other.diasFaltantes == diasFaltantes;

  @override
  int get hashCode => Object.hash(
    experiencia,
    fechaRegistro,
    cumpleAntiguedadEl,
    diasFaltantes,
  );

  @override
  String toString() =>
      'EstadoRunnerExperto($experiencia XP, registro $fechaRegistro, '
      'faltan $diasFaltantes días)';
}
