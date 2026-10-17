import 'package:flutter/material.dart';

/// De qué avisa una notificación.
///
/// Los nombres coinciden con la restricción `tipo in (...)` de la tabla
/// `notificaciones` (`0032_notificaciones.sql`).
enum TipoNotificacion {
  /// El Runner Experto aprobó una ruta y ya la ve la comunidad (criterio 2
  /// de SCRUM-241).
  rutaPublicada('ruta_publicada', Icons.route_outlined),

  /// El Runner Experto no aprobó la ruta. El aviso lo crea la HU de la
  /// revisión; aquí solo se sabe pintarlo.
  rutaRechazada('ruta_rechazada', Icons.unpublished_outlined),

  /// El administrador retiró una publicación del foro, con su motivo
  /// (criterio 2 de SCRUM-242).
  publicacionRetirada('publicacion_retirada', Icons.gavel_outlined);

  const TipoNotificacion(this.valorDb, this.icono);

  final String valorDb;

  /// Con qué se distingue de un vistazo en la bandeja.
  final IconData icono;

  static TipoNotificacion? desdeDb(String? valor) {
    for (final tipo in values) {
      if (tipo.valorDb == valor) return tipo;
    }
    return null;
  }
}

/// Un aviso para el usuario, tal como vive en `notificaciones`.
///
/// El texto viene escrito de la base: lo redacta quien crea el aviso, que es
/// la que sabe el nombre de la ruta o el motivo del retiro.
@immutable
class Notificacion {
  const Notificacion({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.fechaCreacion,
    this.entidadId,
    this.leidaEn,
  });

  final String id;
  final TipoNotificacion tipo;
  final String titulo;
  final String mensaje;
  final DateTime fechaCreacion;

  /// A qué apunta el aviso. Qué cosa es se deduce de [tipo].
  final String? entidadId;

  /// Cuándo la leyó el usuario, o null si todavía no.
  final DateTime? leidaEn;

  bool get leida => leidaEn != null;

  /// Lee una fila de `notificaciones`, o null si es de un tipo que esta
  /// versión de la app no conoce.
  ///
  /// Devolver null en vez de lanzar es a propósito: cuando otra historia
  /// añada un tipo de aviso, una app sin actualizar tiene que seguir
  /// mostrando el resto de la bandeja en vez de quedarse en blanco.
  static Notificacion? desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final tipo = TipoNotificacion.desdeDb(fila['tipo'] as String?);
    final titulo = fila['titulo'];
    final mensaje = fila['mensaje'];
    final fecha = fila['fecha_creacion'];
    final leida = fila['leida_en'];
    final entidad = fila['entidad_id'];

    if (id is! String ||
        tipo == null ||
        titulo is! String ||
        mensaje is! String ||
        fecha is! String) {
      return null;
    }

    return Notificacion(
      id: id,
      tipo: tipo,
      titulo: titulo,
      mensaje: mensaje,
      fechaCreacion: DateTime.parse(fecha).toLocal(),
      entidadId: entidad is String ? entidad : null,
      leidaEn: leida is String ? DateTime.parse(leida).toLocal() : null,
    );
  }

  @override
  bool operator ==(Object other) => other is Notificacion && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Notificacion(${tipo.valorDb}, $titulo)';
}
