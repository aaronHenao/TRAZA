import 'ruta.dart';

/// Cuántos caracteres admite el motivo de un rechazo. Es el mismo límite que
/// `rutas_motivo_rechazo_valido` (`0036`): el motivo viaja en la notificación
/// al autor junto al nombre de la ruta, y los dos tienen que caber.
const maxCaracteresMotivoRechazo = 300;

/// Quién revisa una ruta en cada momento (SCRUM-321).
///
/// La revisión es en orden: primero el administrador y después un Runner
/// Experto. Cada etapa tiene su bandeja y ve solo lo que le toca.
enum EtapaRevision {
  /// La primera: la ruta recién enviada (criterio 2).
  administrador(EstadoRuta.enRevision, 'administrador'),

  /// La segunda: lo que el administrador ya aprobó (criterio 4).
  experto(EstadoRuta.revisionExperto, 'Runner Experto');

  const EtapaRevision(this.estadoPendiente, this.revisor);

  /// En qué estado están las rutas que esperan a esta etapa.
  final EstadoRuta estadoPendiente;

  /// Quién decide, para los textos ("pendiente de revisión del ...").
  final String revisor;
}

/// Cómo se le nombra a cada estado en la app. Son los textos de la HU.
extension EtiquetaEstadoRuta on EstadoRuta {
  String get etiqueta => switch (this) {
    EstadoRuta.enRevision => 'Pendiente de revisión del administrador',
    EstadoRuta.revisionExperto => 'Pendiente de revisión del Runner Experto',
    EstadoRuta.publicada => 'Publicada',
    EstadoRuta.rechazada => 'Rechazada',
  };

  /// Si la ruta sigue esperando a alguien. Ni publicada ni rechazada.
  bool get pendienteDeRevision =>
      this == EstadoRuta.enRevision || this == EstadoRuta.revisionExperto;
}

/// Qué le pasa a un motivo de rechazo antes de mandarlo, o null si se puede
/// mandar.
///
/// Es la misma regla que aplica `decidir_revision_ruta` en la base
/// (criterio 6): se valida aquí para avisar sin ir a la red, pero la barrera
/// de verdad es la base.
String? errorDelMotivo(String? motivo) {
  final limpio = motivo?.trim() ?? '';
  if (limpio.isEmpty) return 'El motivo es obligatorio.';
  if (limpio.length > maxCaracteresMotivoRechazo) {
    return 'El motivo no puede pasar de $maxCaracteresMotivoRechazo '
        'caracteres.';
  }
  return null;
}
