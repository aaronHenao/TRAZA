import 'package:flutter/foundation.dart';

import 'experiencia_ganada.dart';
import 'regla_experiencia.dart';
import 'resumen_entrenamiento.dart';
import 'reto_del_usuario.dart';

/// Cuánto avanzó un reto con el entrenamiento que se acaba de finalizar.
///
/// La base no guarda cuántos km aportó cada entrenamiento a cada reto: el
/// trigger de `0018_xp_solo_por_retos.sql` solo suma al `progreso_km`. Esto
/// lo reconstruye con la misma regla, y por eso solo vale recién finalizado:
/// abierto desde el historial, los entrenamientos posteriores ya movieron el
/// progreso.
@immutable
class AvanceReto {
  const AvanceReto({
    required this.reto,
    required this.kmAportados,
    this.xpGanada,
  });

  /// El reto tal como quedó después del entrenamiento.
  final RetoDelUsuario reto;

  final double kmAportados;

  /// La XP que pagó el reto, si este entrenamiento lo completó.
  final int? xpGanada;

  bool get completadoAhora => xpGanada != null;

  /// Lo que llevaba antes de este entrenamiento, en km.
  double get kmAntes {
    final antes = reto.progresoKm - kmAportados;
    return antes < 0 ? 0 : antes;
  }

  /// Qué parte de la meta llevaba antes, entre 0 y 1.
  double get progresoAntes {
    if (reto.reto.metaKm <= 0) return 0;
    return (kmAntes / reto.reto.metaKm).clamp(0.0, 1.0);
  }

  /// Qué parte de la meta lleva ahora, entre 0 y 1.
  double get progresoDespues => reto.progreso;

  /// Los retos que avanzó el entrenamiento de [resumen], completados primero
  /// y después los que quedaron más cerca de la meta.
  ///
  /// Replica `otorgar_experiencia()`: los km cuentan si el entrenamiento pasó
  /// las validaciones ([xp] con ajuste `ninguno`), y solo para los retos del
  /// mismo tipo de actividad, vigentes ese día y activados antes de
  /// finalizar. Los que completó se reconocen por las filas de XP de [xp].
  static List<AvanceReto> delEntrenamiento({
    required List<RetoDelUsuario> misRetos,
    required ExperienciaDeEntrenamiento xp,
    required ResumenEntrenamiento resumen,
  }) {
    final metros = resumen.distanciaMetros;
    if (xp.ajuste != AjusteExperiencia.ninguno ||
        metros == null ||
        metros <= 0) {
      return const [];
    }
    final km = metros / 1000;
    final xpPorReto = {
      // Uno sin id no se puede cruzar: el usuario ya no ve ese reto.
      for (final completado in xp.retos) ?completado.retoId: completado.xp,
    };

    final avances = <AvanceReto>[];
    for (final mio in misRetos) {
      final xpGanada = xpPorReto[mio.reto.id];
      if (mio.completado && xpGanada != null) {
        avances.add(AvanceReto(reto: mio, kmAportados: km, xpGanada: xpGanada));
      } else if (mio.estado == EstadoRetoUsuario.enProgreso &&
          mio.reto.estaActivo &&
          mio.reto.tipoActividad.nombre == resumen.nombreActividad &&
          mio.reto.vigencia.cubre(resumen.fechaFin) &&
          mio.fechaActivacion.isBefore(resumen.fechaFin)) {
        avances.add(AvanceReto(reto: mio, kmAportados: km));
      }
    }

    avances.sort((a, b) {
      if (a.completadoAhora != b.completadoAhora) {
        return a.completadoAhora ? -1 : 1;
      }
      return b.progresoDespues.compareTo(a.progresoDespues);
    });
    return avances;
  }

  @override
  bool operator ==(Object other) =>
      other is AvanceReto &&
      other.reto == reto &&
      other.kmAportados == kmAportados &&
      other.xpGanada == xpGanada;

  @override
  int get hashCode => Object.hash(reto, kmAportados, xpGanada);

  @override
  String toString() =>
      'AvanceReto(${reto.reto.nombre}, +$kmAportados km, $xpGanada XP)';
}
