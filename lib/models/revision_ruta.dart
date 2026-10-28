/// Cuántos caracteres admite el motivo de un rechazo. Es el mismo límite que
/// `rutas_motivo_rechazo_valido` (`0043`): el motivo viaja en la notificación
/// al autor junto al nombre de la ruta, y los dos tienen que caber.
const maxCaracteresMotivoRechazo = 300;

/// Qué le pasa a un motivo de rechazo antes de mandarlo, o null si se puede
/// mandar.
///
/// Es la misma regla que aplica `decidir_revision_ruta` en la base
/// (criterio 6 de SCRUM-321): se valida aquí para avisar sin ir a la red,
/// pero la barrera de verdad es la base.
String? errorDelMotivo(String? motivo) {
  final limpio = motivo?.trim() ?? '';
  if (limpio.isEmpty) return 'El motivo es obligatorio.';
  if (limpio.length > maxCaracteresMotivoRechazo) {
    return 'El motivo no puede pasar de $maxCaracteresMotivoRechazo '
        'caracteres.';
  }
  return null;
}
