import 'package:flutter/foundation.dart';

/// Qué se moderó: una publicación o un comentario.
enum TipoModeracion {
  publicacion,
  comentario;

  static TipoModeracion? desdeDb(String? valor) =>
      values.where((t) => t.name == valor).firstOrNull;
}

/// Si se moderó el texto recién creado o una edición.
enum AccionModeracion {
  creacion,
  edicion;

  static AccionModeracion? desdeDb(String? valor) =>
      values.where((a) => a.name == valor).firstOrNull;
}

/// En qué va la moderación. Coincide con la restricción de
/// `moderaciones_foro` (`0035_foro_moderacion_ia.sql`).
enum EstadoModeracion {
  /// La IA la está analizando.
  enRevision('en_revision'),

  /// Se publicó (o se aplicó la edición).
  aprobada('aprobada'),

  /// La IA dudó: la decide el administrador.
  pendiente('pendiente'),

  /// Quedó fuera del foro. Cuenta como falta del autor.
  rechazada('rechazada');

  const EstadoModeracion(this.valorDb);

  final String valorDb;

  static EstadoModeracion? desdeDb(String? valor) =>
      values.where((e) => e.valorDb == valor).firstOrNull;
}

/// Quién decidió.
enum ResponsableModeracion {
  ia,
  admin;

  static ResponsableModeracion? desdeDb(String? valor) =>
      values.where((r) => r.name == valor).firstOrNull;
}

/// Una fila de `moderaciones_foro` (SCRUM-322): lo que se analizó, cómo
/// quedó, quién lo decidió, cuándo y por qué.
///
/// Es a la vez la cola de la moderación, el historial que audita el
/// administrador y la lista de "Mis rechazados" del autor. Las faltas de un
/// usuario son sus moderaciones [EstadoModeracion.rechazada] (SCRUM-338).
@immutable
class ModeracionForo {
  const ModeracionForo({
    required this.id,
    required this.tipo,
    required this.publicacionId,
    required this.autorId,
    required this.autorNombre,
    required this.accion,
    required this.contenido,
    required this.estado,
    required this.fechaSolicitud,
    this.comentarioId,
    this.titulo,
    this.motivo,
    this.categorias = const [],
    this.responsable,
    this.responsableNombre,
    this.fechaDecision,
    this.vistaPorAutor = false,
  });

  final String id;
  final TipoModeracion tipo;

  /// La publicación moderada, o la comentada si [tipo] es un comentario.
  final String publicacionId;
  final String? comentarioId;
  final String autorId;
  final String autorNombre;
  final AccionModeracion accion;

  /// Copia del texto que se analizó. En una edición todavía no aprobada es
  /// el único lugar donde existe el texto nuevo.
  final String? titulo;
  final String contenido;

  final EstadoModeracion estado;

  /// Por qué se rechazó. En lo pendiente, la duda de la IA (para el
  /// administrador).
  final String? motivo;

  /// Tipo de infracción, en español (criterio 4 de SCRUM-322).
  final List<String> categorias;

  final ResponsableModeracion? responsable;

  /// Copia del nombre de quien decidió: "Moderación automática" o el del
  /// administrador.
  final String? responsableNombre;
  final DateTime fechaSolicitud;
  final DateTime? fechaDecision;

  /// El autor ya vio el rechazo en "Mis rechazados".
  final bool vistaPorAutor;

  /// Sigue sin veredicto final.
  bool get abierta =>
      estado == EstadoModeracion.enRevision ||
      estado == EstadoModeracion.pendiente;

  bool get rechazada => estado == EstadoModeracion.rechazada;

  bool get esEdicion => accion == AccionModeracion.edicion;

  /// Lo que se moderó, dicho para el autor y el administrador.
  String get queEs => switch ((tipo, accion)) {
    (TipoModeracion.publicacion, AccionModeracion.creacion) => 'Publicación',
    (TipoModeracion.publicacion, AccionModeracion.edicion) =>
      'Edición de publicación',
    (TipoModeracion.comentario, AccionModeracion.creacion) => 'Comentario',
    (TipoModeracion.comentario, AccionModeracion.edicion) =>
      'Edición de comentario',
  };

  /// Quién decidió, como lo lee el autor: la IA o "el administrador", sin
  /// su nombre.
  String? get responsableParaElAutor => switch (responsable) {
    ResponsableModeracion.ia => 'Moderación automática',
    ResponsableModeracion.admin => 'Administrador',
    null => null,
  };

  /// Quién decidió, como lo lee el administrador: con el nombre de quien
  /// rechazó o aprobó.
  String? get responsableParaElAdmin => switch (responsable) {
    ResponsableModeracion.ia => 'Moderación automática (IA)',
    ResponsableModeracion.admin =>
      'Administrador · ${responsableNombre ?? 'sin nombre'}',
    null => null,
  };

  factory ModeracionForo.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final tipo = TipoModeracion.desdeDb(fila['tipo'] as String?);
    final publicacionId = fila['publicacion_id'];
    final comentarioId = fila['comentario_id'];
    final autorId = fila['autor_id'];
    final autorNombre = fila['autor_nombre'];
    final accion = AccionModeracion.desdeDb(fila['accion'] as String?);
    final titulo = fila['titulo'];
    final contenido = fila['contenido'];
    final estado = EstadoModeracion.desdeDb(fila['estado'] as String?);
    final motivo = fila['motivo'];
    final categorias = fila['categorias'];
    final responsable = fila['responsable'];
    final responsableNombre = fila['responsable_nombre'];
    final solicitud = fila['fecha_solicitud'];
    final decision = fila['fecha_decision'];

    if (id is! String ||
        tipo == null ||
        publicacionId is! String ||
        (comentarioId != null && comentarioId is! String) ||
        autorId is! String ||
        autorNombre is! String ||
        accion == null ||
        (titulo != null && titulo is! String) ||
        contenido is! String ||
        estado == null ||
        (motivo != null && motivo is! String) ||
        (categorias != null && categorias is! List) ||
        (responsable != null &&
            ResponsableModeracion.desdeDb(responsable as String?) == null) ||
        (responsableNombre != null && responsableNombre is! String) ||
        solicitud is! String ||
        (decision != null && decision is! String)) {
      throw FormatException(
        'Fila de moderaciones_foro incompleta o inesperada',
        fila,
      );
    }

    return ModeracionForo(
      id: id,
      tipo: tipo,
      publicacionId: publicacionId,
      comentarioId: comentarioId as String?,
      autorId: autorId,
      autorNombre: autorNombre,
      accion: accion,
      titulo: titulo as String?,
      contenido: contenido,
      estado: estado,
      motivo: motivo as String?,
      categorias: [...?(categorias as List?)?.whereType<String>()],
      responsable: ResponsableModeracion.desdeDb(responsable as String?),
      responsableNombre: responsableNombre as String?,
      fechaSolicitud: DateTime.parse(solicitud).toLocal(),
      fechaDecision: decision is String
          ? DateTime.parse(decision).toLocal()
          : null,
      vistaPorAutor: fila['vista_por_autor'] == true,
    );
  }

  @override
  bool operator ==(Object other) => other is ModeracionForo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ModeracionForo($queEs, ${estado.valorDb})';
}

/// Cuántas faltas tiene [autorId] entre [moderaciones] (SCRUM-338).
int faltasDe(String autorId, Iterable<ModeracionForo> moderaciones) =>
    moderaciones.where((m) => m.autorId == autorId && m.rechazada).length;
