import 'package:flutter/material.dart';

import 'reto.dart';

/// En qué va un corredor con un reto que activó.
///
/// Los nombres coinciden con la restricción `estado in ('en_progreso',
/// 'completado', 'vencido')` de `retos_usuario`.
enum EstadoRetoUsuario {
  enProgreso('en_progreso'),
  completado('completado'),
  vencido('vencido');

  const EstadoRetoUsuario(this.valorDb);

  final String valorDb;

  static EstadoRetoUsuario? desdeDb(String? valor) {
    for (final estado in values) {
      if (estado.valorDb == valor) return estado;
    }
    return null;
  }
}

/// Un reto que el corredor activó, con lo que lleva hecho.
///
/// Junta la fila de `retos_usuario` con el reto al que apunta: sin el reto no
/// se sabe ni la meta ni la vigencia, que es lo que da sentido al progreso.
@immutable
class RetoDelUsuario {
  const RetoDelUsuario({
    required this.reto,
    required this.estado,
    required this.progresoKm,
    required this.fechaActivacion,
    this.fechaCompletado,
  });

  final Reto reto;
  final EstadoRetoUsuario estado;
  final double progresoKm;
  final DateTime fechaActivacion;

  /// Cuándo lo completó. Nulo mientras no lo haya hecho.
  final DateTime? fechaCompletado;

  bool get completado => estado == EstadoRetoUsuario.completado;

  /// Qué parte de la meta lleva, entre 0 y 1.
  ///
  /// Se recorta en 1: pasarse de la meta llena la barra, no la desborda.
  double get progreso {
    if (reto.metaKm <= 0) return 0;
    return (progresoKm / reto.metaKm).clamp(0.0, 1.0);
  }

  /// Si se acabó el plazo sin completarlo (SCRUM-173).
  ///
  /// No basta con mirar `estado`: pasar una fila a `vencido` requeriría un
  /// proceso que recorra la tabla cada noche, y ese proceso no existe. Aquí
  /// se deduce del calendario, que siempre está al día.
  bool vencidoEn(DateTime ahora) {
    if (completado) return false;
    return estado == EstadoRetoUsuario.vencido ||
        reto.vigencia.diasRestantesDesde(ahora) == 0;
  }

  /// Si todavía se puede cumplir.
  bool enCursoEn(DateTime ahora) => !completado && !vencidoEn(ahora);

  /// Lee una fila de `retos_usuario` con su reto embebido.
  ///
  /// Lanza [FormatException] si falta algo: las columnas son `not null`, así
  /// que una fila que no encaje significa que el esquema y esta clase se
  /// desalinearon.
  factory RetoDelUsuario.desdeSupabase(Map<String, dynamic> fila) {
    final estado = EstadoRetoUsuario.desdeDb(fila['estado'] as String?);
    final reto = fila['retos'];
    final progreso = fila['progreso_km'];
    final activacion = fila['fecha_activacion'];
    final completado = fila['fecha_completado'];

    if (estado == null ||
        reto is! Map<String, dynamic> ||
        progreso is! num ||
        activacion is! String) {
      throw FormatException('Fila de retos_usuario incompleta', fila);
    }

    return RetoDelUsuario(
      reto: Reto.desdeSupabase(reto),
      estado: estado,
      progresoKm: progreso.toDouble(),
      fechaActivacion: DateTime.parse(activacion).toLocal(),
      fechaCompletado: completado is String
          ? DateTime.parse(completado).toLocal()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RetoDelUsuario &&
      other.reto.id == reto.id &&
      other.estado == estado &&
      other.progresoKm == progresoKm;

  @override
  int get hashCode => Object.hash(reto.id, estado, progresoKm);

  @override
  String toString() => 'RetoDelUsuario(${reto.nombre}, ${estado.valorDb})';
}

/// Las tres caras del historial de retos.
///
/// No hay "Todos": mezclar lo que se puede cumplir con lo que ya no se puede
/// obliga a leerlo todo para encontrar lo que importa.
enum SeccionHistorialRetos {
  enCurso(
    etiqueta: 'En curso',
    iconoVacio: Icons.directions_run,
    tituloVacio: 'No tienes retos en curso',
    detalleVacio: 'Activa uno desde el catálogo para empezar.',
  ),
  completados(
    etiqueta: 'Completados',
    iconoVacio: Icons.emoji_events_outlined,
    tituloVacio: 'Aún no has completado ningún reto',
    detalleVacio: 'Los que cumplas aparecerán aquí, agrupados por fecha.',
  ),
  vencidos(
    etiqueta: 'Vencidos',
    iconoVacio: Icons.schedule,
    tituloVacio: 'No se te ha vencido ningún reto',
    detalleVacio: 'Aquí van los que se acaben antes de que los completes.',
  );

  const SeccionHistorialRetos({
    required this.etiqueta,
    required this.iconoVacio,
    required this.tituloVacio,
    required this.detalleVacio,
  });

  final String etiqueta;

  /// Qué mostrar cuando esta pestaña no tiene nada. Cada una dice lo suyo:
  /// un mensaje genérico obliga a mirar qué chip está activo para entenderlo.
  final IconData iconoVacio;
  final String tituloVacio;
  final String detalleVacio;

  /// Los retos de [todos] que caen en esta sección.
  List<RetoDelUsuario> filtrar(List<RetoDelUsuario> todos, DateTime ahora) =>
      switch (this) {
        SeccionHistorialRetos.enCurso =>
          todos.where((reto) => reto.enCursoEn(ahora)).toList(),
        SeccionHistorialRetos.completados =>
          todos.where((reto) => reto.completado).toList(),
        SeccionHistorialRetos.vencidos =>
          todos.where((reto) => reto.vencidoEn(ahora)).toList(),
      };
}
