/// En qué punto está un permiso del sistema.
enum EstadoPermiso {
  /// Todavía no se ha consultado al sistema.
  desconocido,

  concedido,

  /// El usuario lo negó, pero se le puede volver a preguntar.
  denegado,

  /// El sistema ya no muestra la ventana (Android tras negarlo dos veces, iOS
  /// tras negarlo una). Solo se puede activar desde los ajustes del teléfono.
  bloqueado,
}

/// Permisos que usa la app (SCRUM-37).
class EstadoPermisos {
  const EstadoPermisos({
    this.ubicacion = EstadoPermiso.desconocido,
    this.solicitandoUbicacion = false,
  });

  final EstadoPermiso ubicacion;

  /// La ventana del sistema está abierta: evita pedirlo dos veces seguidas.
  final bool solicitandoUbicacion;

  EstadoPermisos copyWith({
    EstadoPermiso? ubicacion,
    bool? solicitandoUbicacion,
  }) {
    return EstadoPermisos(
      ubicacion: ubicacion ?? this.ubicacion,
      solicitandoUbicacion: solicitandoUbicacion ?? this.solicitandoUbicacion,
    );
  }
}
