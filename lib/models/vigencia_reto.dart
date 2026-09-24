import 'package:flutter/foundation.dart';

/// Período durante el que un reto está vigente.
///
/// Son fechas sin hora: las columnas `fecha_inicio` y `fecha_fin` de la tabla
/// `retos` son de tipo `date`. Ambos extremos son inclusivos — un reto diario
/// empieza y termina el mismo día.
@immutable
class VigenciaReto {
  VigenciaReto({required DateTime inicio, required DateTime fin})
    : inicio = soloFecha(inicio),
      fin = soloFecha(fin);

  final DateTime inicio;
  final DateTime fin;

  /// Cuántos días cubre, contando el primero y el último.
  int get dias => fin.difference(inicio).inDays + 1;

  /// Si [dia] cae dentro del período.
  bool cubre(DateTime dia) {
    final fecha = soloFecha(dia);
    return !fecha.isBefore(inicio) && !fecha.isAfter(fin);
  }

  /// La misma vigencia con la fecha de fin movida a [nuevaFin].
  ///
  /// Solo hacia adelante: acortar la vigencia dejaría fuera a quien ya iba
  /// cumpliendo el reto. Devuelve null si [nuevaFin] no la extiende.
  VigenciaReto? extendidaHasta(DateTime nuevaFin) {
    final fecha = soloFecha(nuevaFin);
    if (!fecha.isAfter(fin)) return null;
    return VigenciaReto(inicio: inicio, fin: fecha);
  }

  /// `2026-09-22`, como lo espera una columna `date` de Postgres.
  static String aTexto(DateTime fecha) {
    final f = soloFecha(fecha);
    final mes = f.month.toString().padLeft(2, '0');
    final dia = f.day.toString().padLeft(2, '0');
    return '${f.year}-$mes-$dia';
  }

  String get inicioTexto => aTexto(inicio);
  String get finTexto => aTexto(fin);

  /// Lee lo que devuelve Supabase para una columna `date`.
  static DateTime desdeTexto(String valor) {
    final fecha = DateTime.parse(valor);
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  /// Quita la hora y deja la fecha en horario local.
  ///
  /// Todo el cálculo de vigencia trabaja así: el día del usuario es el de su
  /// calendario, no el de UTC. Sin esto, un reto creado de noche en Colombia
  /// (UTC-5) se registraría con la fecha del día siguiente.
  static DateTime soloFecha(DateTime momento) {
    final local = momento.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  @override
  bool operator ==(Object other) =>
      other is VigenciaReto && other.inicio == inicio && other.fin == fin;

  @override
  int get hashCode => Object.hash(inicio, fin);

  @override
  String toString() => 'VigenciaReto($inicioTexto → $finTexto)';
}
