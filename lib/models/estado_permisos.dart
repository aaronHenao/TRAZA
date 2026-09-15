/// Permisos que pide la app. [valorDb] es el de `permisos_usuario.tipo_permiso`.
enum TipoPermiso {
  ubicacion('ubicacion'),
  salud('salud');

  const TipoPermiso(this.valorDb);

  final String valorDb;
}

/// En qué punto está un permiso del sistema.
enum EstadoPermiso {
  /// Todavía no se sabe. iOS, además, nunca revela si se negó la lectura de
  /// datos de salud: ahí se queda en este valor.
  desconocido,

  concedido,

  /// El usuario lo negó, pero se le puede volver a preguntar.
  denegado,

  /// El sistema ya no muestra la ventana (Android tras negarlo dos veces, iOS
  /// tras negarlo una). Solo se puede activar desde los ajustes del teléfono.
  bloqueado,

  /// El dispositivo no lo soporta: web, escritorio, o un Android sin Health
  /// Connect instalado.
  noDisponible,
}

/// Permisos que usa la app (SCRUM-37).
class EstadoPermisos {
  const EstadoPermisos({
    this.ubicacion = EstadoPermiso.desconocido,
    this.salud = EstadoPermiso.desconocido,
    this.solicitandoUbicacion = false,
    this.solicitandoSalud = false,
    this.consultado = false,
    this.saludOmitida = false,
  });

  final EstadoPermiso ubicacion;
  final EstadoPermiso salud;

  /// La ventana del sistema está abierta: evita pedirlo dos veces seguidas.
  final bool solicitandoUbicacion;
  final bool solicitandoSalud;

  /// Ya se le preguntó al sistema al menos una vez. Antes de eso
  /// [EstadoPermiso.desconocido] no significa nada: evita mostrar un aviso de
  /// "falta el permiso" durante el instante que tarda la consulta.
  final bool consultado;

  /// El usuario eligió entrenar sin datos de salud (SCRUM-83). Dura mientras
  /// la app esté abierta: no se le vuelve a preguntar en cada entrenamiento.
  final bool saludOmitida;

  EstadoPermisos copyWith({
    EstadoPermiso? ubicacion,
    EstadoPermiso? salud,
    bool? solicitandoUbicacion,
    bool? solicitandoSalud,
    bool? consultado,
    bool? saludOmitida,
  }) {
    return EstadoPermisos(
      ubicacion: ubicacion ?? this.ubicacion,
      salud: salud ?? this.salud,
      solicitandoUbicacion: solicitandoUbicacion ?? this.solicitandoUbicacion,
      solicitandoSalud: solicitandoSalud ?? this.solicitandoSalud,
      consultado: consultado ?? this.consultado,
      saludOmitida: saludOmitida ?? this.saludOmitida,
    );
  }
}
