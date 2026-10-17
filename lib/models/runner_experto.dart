import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'nivel.dart';
import 'progresion.dart';

/// Lo que pide el rol Runner Experto (SCRUM-210).
///
/// Aquí solo se muestran: quien los comprueba y otorga el rol es
/// `evaluar_rol_experto()` (`0012_rol_experto.sql`, SCRUM-227), porque con la
/// publishable key cualquiera habla con Postgres y lo que solo esté en Dart no
/// está validado. Los números tienen que ser los mismos que las constantes de
/// esa función: si no, la pantalla prometería una cosa y la base haría otra.
abstract final class RequisitosRunnerExperto {
  /// Niveles del mapa de progresión que hay que haber alcanzado. Son 11
  /// porque el requisito es superar el décimo nivel, no llegar a él.
  static const nivelesAlcanzados = 11;

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
/// Solo compara: la experiencia la acredita el motor de XP (SCRUM-192), los
/// niveles los registra el administrador (SCRUM-177) y la fecha de registro es
/// la de la cuenta. No otorga el rol; que cumpla los requisitos es
/// [desbloqueado], nada más.
@immutable
class EstadoRunnerExperto {
  const EstadoRunnerExperto._({
    required this.experiencia,
    required this.nivelesAlcanzados,
    required this.nivelActual,
    required this.nivelesEnMapa,
    required this.fechaRegistro,
    required this.cumpleAntiguedadEl,
    required this.diasFaltantes,
    required this.avanceAntiguedad,
  });

  /// Ubica [experiencia], los [niveles] del mapa y [fechaRegistro] frente a
  /// los requisitos, visto desde [ahora]. [niveles] puede venir en cualquier
  /// orden.
  ///
  /// Un nivel está alcanzado cuando la XP cubre su umbral: la misma cuenta que
  /// hacen el mapa de progresión (SCRUM-226) y `evaluar_rol_experto()`.
  ///
  /// La antigüedad se cuenta en días del calendario, no en horas: quien se
  /// registró el 15 de marzo cumple seis meses el 15 de septiembre, a
  /// cualquier hora. Si ese día no existe (31 de agosto más seis meses), se
  /// toma el último del mes.
  factory EstadoRunnerExperto.calcular({
    required int experiencia,
    required List<Nivel> niveles,
    required DateTime fechaRegistro,
    required DateTime ahora,
  }) {
    final alcanzados = niveles
        .where((nivel) => nivel.umbralExperiencia <= experiencia)
        .length;
    final progresion = Progresion.calcular(
      experiencia: experiencia,
      niveles: niveles,
    );

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
      nivelesAlcanzados: alcanzados,
      nivelActual: progresion.nivelActual,
      nivelesEnMapa: niveles.length,
      fechaRegistro: registro,
      cumpleAntiguedadEl: cumpleEl,
      diasFaltantes: math.max(0, _diasEntre(hoy, cumpleEl)),
      avanceAntiguedad: (transcurridos / total).clamp(0.0, 1.0),
    );
  }

  /// La experiencia acumulada, tal cual se la entregaron.
  final int experiencia;

  /// Cuántos niveles del mapa ya alcanzó. Es también el número del nivel en
  /// el que va: con 4 alcanzados va en el nivel 4.
  final int nivelesAlcanzados;

  /// El nivel en el que va, o null si todavía no alcanza el primero.
  final Nivel? nivelActual;

  /// Cuántos niveles tiene hoy el mapa. Puede ser menos de los que pide el
  /// requisito si el administrador aún no los registró.
  final int nivelesEnMapa;

  /// El día en que se creó la cuenta.
  final DateTime fechaRegistro;

  /// El día desde el que cumple la antigüedad.
  final DateTime cumpleAntiguedadEl;

  /// Días que faltan para cumplir la antigüedad. Cero si ya la cumple.
  final int diasFaltantes;

  /// Qué parte de la antigüedad lleva, de 0 a 1.
  final double avanceAntiguedad;

  bool get cumpleNiveles =>
      nivelesAlcanzados >= RequisitosRunnerExperto.nivelesAlcanzados;

  bool get cumpleExperiencia =>
      experiencia >= RequisitosRunnerExperto.experiencia;

  bool get cumpleAntiguedad => diasFaltantes == 0;

  /// Si cumple los tres requisitos (criterio 3 de SCRUM-195).
  bool get desbloqueado =>
      cumpleNiveles && cumpleExperiencia && cumpleAntiguedad;

  /// Niveles que le faltan por alcanzar. Cero si ya los tiene.
  int get nivelesFaltantes => math.max(
    0,
    RequisitosRunnerExperto.nivelesAlcanzados - nivelesAlcanzados,
  );

  /// Si el mapa todavía no tiene niveles suficientes para cumplir el
  /// requisito, por mucha XP que gane.
  bool get faltanNivelesEnMapa =>
      nivelesEnMapa < RequisitosRunnerExperto.nivelesAlcanzados;

  /// Qué parte de los niveles lleva, de 0 a 1.
  double get avanceNiveles =>
      (nivelesAlcanzados / RequisitosRunnerExperto.nivelesAlcanzados).clamp(
        0.0,
        1.0,
      );

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
      other.nivelesAlcanzados == nivelesAlcanzados &&
      other.nivelActual == nivelActual &&
      other.nivelesEnMapa == nivelesEnMapa &&
      other.fechaRegistro == fechaRegistro &&
      other.cumpleAntiguedadEl == cumpleAntiguedadEl &&
      other.diasFaltantes == diasFaltantes;

  @override
  int get hashCode => Object.hash(
    experiencia,
    nivelesAlcanzados,
    nivelActual,
    nivelesEnMapa,
    fechaRegistro,
    cumpleAntiguedadEl,
    diasFaltantes,
  );

  @override
  String toString() =>
      'EstadoRunnerExperto($experiencia XP, $nivelesAlcanzados de '
      '$nivelesEnMapa niveles, registro $fechaRegistro, '
      'faltan $diasFaltantes días)';
}
