import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/version_publicacion.dart';
import 'package:traza/services/foro_service.dart';

/// Doble de `ForoRepository` con el foro en memoria.
///
/// Anota lo que recibe, lanza [error] si se le indica y crea las
/// publicaciones con el [estadoAlCrear] que la prueba quiera simular que puso
/// la base.
///
/// Las ediciones se comportan como `editar_*_foro` (SCRUM-322): las de un
/// corredor quedan en [moderacionesGuardadas] sin tocar lo publicado; las del
/// administrador ([comoAdmin]) se aplican de una vez.
class ForoRepositorioFalso implements ForoRepository {
  ForoRepositorioFalso({
    List<PublicacionForo>? publicaciones,
    List<ModeracionForo>? moderaciones,
    this.estadoAlCrear = EstadoPublicacion.publicada,
    this.ahora,
  }) : publicaciones = [...?publicaciones],
       moderacionesGuardadas = [...?moderaciones];

  final List<PublicacionForo> publicaciones;
  EstadoPublicacion estadoAlCrear;
  DateTime? ahora;

  /// Quien usa el repositorio, como `auth.uid()`.
  static const usuario = 'usuario-1';

  Object? error;
  NuevaPublicacion? recibida;
  int consultas = 0;

  DateTime get _ahora => ahora ?? DateTime(2026, 10, 16, 12);

  @override
  Future<PublicacionForo> crear(NuevaPublicacion publicacion) async {
    recibida = publicacion;
    final error = this.error;
    if (error != null) throw error;

    final creada = PublicacionForo(
      id: 'pub-${publicaciones.length + 1}',
      autorId: usuario,
      autorNombre: 'Ana Runner',
      titulo: publicacion.titulo,
      contenido: publicacion.contenido,
      estado: estadoAlCrear,
      fechaCreacion: ahora ?? DateTime(2026, 10, 16, 9),
      autorEsAdmin: comoAdmin,
    );
    publicaciones.insert(0, creada);
    return creada;
  }

  @override
  Future<List<PublicacionForo>> publicadas() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    // Como la consulta: lo publicado y lo propio que espera la moderación.
    return publicaciones
        .where(
          (p) =>
              p.estado == EstadoPublicacion.publicada ||
              (p.autorId == usuario && p.estado.esperaModeracion),
        )
        .toList();
  }

  @override
  Future<List<PublicacionForo>> todasParaModeracion() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return [...publicaciones];
  }

  /// Comentarios por id de publicación.
  final Map<String, List<ComentarioForo>> comentariosDe = {};

  NuevoComentario? comentarioRecibido;

  /// Error que lanza solo `comentar`, para simular que la publicación dejó
  /// de estar disponible mientras se escribía.
  Object? errorAlComentar;

  /// El estado con que la base deja los comentarios nuevos (SCRUM-322).
  EstadoPublicacion estadoAlComentar = EstadoPublicacion.publicada;

  /// Simula que quien publica o comenta es el administrador: la base le pone
  /// `autor_es_admin` y sus ediciones no pasan por la moderación.
  bool comoAdmin = false;

  @override
  Future<PublicacionForo?> publicacion(String id) async {
    final error = this.error;
    if (error != null) throw error;
    for (final p in publicaciones) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<ComentarioForo>> comentarios(String publicacionId) async {
    final error = this.error;
    if (error != null) throw error;
    return [...?comentariosDe[publicacionId]];
  }

  @override
  Future<ComentarioForo> comentar(NuevoComentario comentario) async {
    comentarioRecibido = comentario;
    final error = errorAlComentar ?? this.error;
    if (error != null) throw error;

    final lista = comentariosDe.putIfAbsent(comentario.publicacionId, () => []);
    final creado = ComentarioForo(
      id: 'com-${lista.length + 1}',
      publicacionId: comentario.publicacionId,
      autorId: usuario,
      autorNombre: 'Ana Runner',
      contenido: comentario.contenido,
      fechaCreacion: ahora ?? DateTime(2026, 10, 16, 9),
      autorEsAdmin: comoAdmin,
      estado: estadoAlComentar,
    );
    lista.add(creado);
    return creado;
  }

  NuevaPublicacion? edicionRecibida;

  /// Error que lanza solo `editar`.
  Object? errorAlEditar;

  @override
  Future<ModeracionForo?> editar(String id, NuevaPublicacion cambios) async {
    edicionRecibida = cambios;
    final error = errorAlEditar ?? this.error;
    if (error != null) throw error;

    final i = publicaciones.indexWhere((p) => p.id == id);
    if (i < 0 || publicaciones[i].estado != EstadoPublicacion.publicada) {
      throw const PublicacionNoDisponibleException();
    }
    final p = publicaciones[i];
    if (p.titulo == cambios.titulo && p.contenido == cambios.contenido) {
      return null;
    }
    if (_edicionAbierta(id)) throw const EdicionYaEnRevisionException();

    final moderacion = _guardarModeracion(
      tipo: TipoModeracion.publicacion,
      publicacionId: id,
      autorId: p.autorId,
      autorNombre: p.autorNombre,
      titulo: cambios.titulo,
      contenido: cambios.contenido,
    );
    if (comoAdmin) _aplicarEdicionPublicacion(id, cambios);
    return moderacion;
  }

  void _aplicarEdicionPublicacion(String id, NuevaPublicacion cambios) {
    final i = publicaciones.indexWhere((p) => p.id == id);
    final p = publicaciones[i];
    // Como el trigger: la versión anterior va al historial.
    versionesDe
        .putIfAbsent(id, () => [])
        .insert(
          0,
          VersionPublicacion(
            id: 'ver-${versionesDe[id]!.length + 1}',
            titulo: p.titulo,
            contenido: p.contenido,
            vigenteDesde: p.fechaEdicion ?? p.fechaCreacion,
          ),
        );
    publicaciones[i] = PublicacionForo(
      id: p.id,
      autorId: p.autorId,
      autorNombre: p.autorNombre,
      titulo: cambios.titulo,
      contenido: cambios.contenido,
      estado: p.estado,
      fechaCreacion: p.fechaCreacion,
      autorEsAdmin: p.autorEsAdmin,
      fechaEdicion: _ahora,
    );
  }

  /// Versiones anteriores por id de publicación, de la más reciente a la
  /// original.
  final Map<String, List<VersionPublicacion>> versionesDe = {};

  @override
  Future<List<VersionPublicacion>> versiones(String publicacionId) async {
    final error = this.error;
    if (error != null) throw error;
    return [...?versionesDe[publicacionId]];
  }

  NuevoComentario? edicionComentarioRecibida;

  /// Error que lanza solo `editarComentario`.
  Object? errorAlEditarComentario;

  /// Versiones anteriores por id de comentario, de la más reciente a la
  /// original.
  final Map<String, List<VersionComentario>> versionesComentarioDe = {};

  @override
  Future<ModeracionForo?> editarComentario(
    String id,
    NuevoComentario cambios,
  ) async {
    edicionComentarioRecibida = cambios;
    final error = errorAlEditarComentario ?? this.error;
    if (error != null) throw error;

    for (final lista in comentariosDe.values) {
      final i = lista.indexWhere((c) => c.id == id);
      if (i < 0) continue;
      final c = lista[i];
      if (c.contenido == cambios.contenido) return null;
      if (_edicionAbierta(id)) throw const EdicionYaEnRevisionException();

      final moderacion = _guardarModeracion(
        tipo: TipoModeracion.comentario,
        publicacionId: c.publicacionId,
        comentarioId: id,
        autorId: c.autorId,
        autorNombre: c.autorNombre,
        contenido: cambios.contenido,
      );
      if (comoAdmin) {
        // Como el trigger: la versión anterior va al historial.
        versionesComentarioDe
            .putIfAbsent(id, () => [])
            .insert(
              0,
              VersionComentario(
                id: 'vc-${versionesComentarioDe[id]!.length + 1}',
                contenido: c.contenido,
                vigenteDesde: c.fechaEdicion ?? c.fechaCreacion,
              ),
            );
        lista[i] = ComentarioForo(
          id: c.id,
          publicacionId: c.publicacionId,
          autorId: c.autorId,
          autorNombre: c.autorNombre,
          contenido: cambios.contenido,
          fechaCreacion: c.fechaCreacion,
          autorEsAdmin: c.autorEsAdmin,
          fechaEdicion: _ahora,
        );
      }
      return moderacion;
    }
    throw const PublicacionNoDisponibleException();
  }

  @override
  Future<List<VersionComentario>> versionesComentario(
    String comentarioId,
  ) async {
    final error = this.error;
    if (error != null) throw error;
    return [...?versionesComentarioDe[comentarioId]];
  }

  /// `moderaciones_foro` en memoria (SCRUM-322).
  final List<ModeracionForo> moderacionesGuardadas;

  bool _edicionAbierta(String id) => moderacionesGuardadas.any(
    (m) =>
        m.esEdicion && m.abierta && (m.comentarioId ?? m.publicacionId) == id,
  );

  ModeracionForo _guardarModeracion({
    required TipoModeracion tipo,
    required String publicacionId,
    required String autorId,
    required String autorNombre,
    required String contenido,
    String? comentarioId,
    String? titulo,
  }) {
    final moderacion = moderacionDePrueba(
      id: 'mod-${moderacionesGuardadas.length + 1}',
      tipo: tipo,
      publicacionId: publicacionId,
      comentarioId: comentarioId,
      autorId: autorId,
      autorNombre: autorNombre,
      accion: AccionModeracion.edicion,
      titulo: titulo,
      contenido: contenido,
      estado: comoAdmin
          ? EstadoModeracion.aprobada
          : EstadoModeracion.enRevision,
      motivo: null,
      categorias: const [],
      responsable: comoAdmin ? ResponsableModeracion.admin : null,
      responsableNombre: comoAdmin ? autorNombre : null,
      fechaSolicitud: _ahora,
      fechaDecision: comoAdmin ? _ahora : null,
    );
    moderacionesGuardadas.insert(0, moderacion);
    return moderacion;
  }

  /// Las pruebas tienen un solo usuario: toda la moderación guardada es
  /// "suya". Las que mezclan autores filtran por `autorId`, como la app.
  @override
  Future<List<ModeracionForo>> misModeraciones() async {
    final error = this.error;
    if (error != null) throw error;
    return [...moderacionesGuardadas];
  }

  @override
  Future<List<ModeracionForo>> moderaciones() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return [...moderacionesGuardadas];
  }

  /// Lo que recibió `decidir`: (id, aprobar, motivo).
  (String, bool, String?)? decisionRecibida;

  @override
  Future<ModeracionForo> decidir(
    String moderacionId, {
    required bool aprobar,
    String? motivo,
  }) async {
    decisionRecibida = (moderacionId, aprobar, motivo);
    final error = this.error;
    if (error != null) throw error;

    final i = moderacionesGuardadas.indexWhere((m) => m.id == moderacionId);
    if (i < 0 || !moderacionesGuardadas[i].abierta) {
      throw const ModeracionYaResueltaException();
    }
    final m = moderacionesGuardadas[i];
    final decidida = moderacionDePrueba(
      id: m.id,
      tipo: m.tipo,
      publicacionId: m.publicacionId,
      comentarioId: m.comentarioId,
      autorId: m.autorId,
      autorNombre: m.autorNombre,
      accion: m.accion,
      titulo: m.titulo,
      contenido: m.contenido,
      estado: aprobar ? EstadoModeracion.aprobada : EstadoModeracion.rechazada,
      motivo: aprobar ? null : motivo,
      categorias: aprobar ? const [] : m.categorias,
      responsable: ResponsableModeracion.admin,
      responsableNombre: 'Admin TRAZA',
      fechaSolicitud: m.fechaSolicitud,
      fechaDecision: _ahora,
    );
    moderacionesGuardadas[i] = decidida;

    // Como `resolver_moderacion`: una publicación nueva cambia de estado.
    if (m.tipo == TipoModeracion.publicacion &&
        m.accion == AccionModeracion.creacion) {
      _cambiarEstado(
        m.publicacionId,
        aprobar ? EstadoPublicacion.publicada : EstadoPublicacion.rechazada,
        aprobar ? null : motivo,
      );
    }
    return decidida;
  }

  int rechazosMarcados = 0;

  @override
  Future<void> marcarRechazosVistos() async {
    rechazosMarcados++;
    for (var i = 0; i < moderacionesGuardadas.length; i++) {
      final m = moderacionesGuardadas[i];
      if (!m.rechazada || m.vistaPorAutor) continue;
      moderacionesGuardadas[i] = moderacionDePrueba(
        id: m.id,
        tipo: m.tipo,
        publicacionId: m.publicacionId,
        comentarioId: m.comentarioId,
        autorId: m.autorId,
        autorNombre: m.autorNombre,
        accion: m.accion,
        titulo: m.titulo,
        contenido: m.contenido,
        estado: m.estado,
        motivo: m.motivo,
        categorias: m.categorias,
        responsable: m.responsable,
        responsableNombre: m.responsableNombre,
        fechaSolicitud: m.fechaSolicitud,
        fechaDecision: m.fechaDecision,
        vistaPorAutor: true,
      );
    }
  }

  /// Simula que la moderación rechazó la publicación [id] (SCRUM-322).
  void rechazar(String id, {String? motivo}) =>
      _cambiarEstado(id, EstadoPublicacion.rechazada, motivo);

  void _cambiarEstado(String id, EstadoPublicacion estado, String? motivo) {
    final i = publicaciones.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final p = publicaciones[i];
    publicaciones[i] = PublicacionForo(
      id: p.id,
      autorId: p.autorId,
      autorNombre: p.autorNombre,
      titulo: p.titulo,
      contenido: p.contenido,
      estado: estado,
      fechaCreacion: p.fechaCreacion,
      motivoModeracion: motivo,
      autorEsAdmin: p.autorEsAdmin,
      fechaEdicion: p.fechaEdicion,
    );
  }
}

/// Un comentario de ejemplo para las pruebas.
ComentarioForo comentarioDePrueba({
  String id = 'com-1',
  String publicacionId = 'pub-1',
  String? autorId,
  String autorNombre = 'Lucía',
  String contenido = 'Prueba con unos de drop bajo.',
  DateTime? fecha,
  bool autorEsAdmin = false,
  DateTime? fechaEdicion,
  EstadoPublicacion estado = EstadoPublicacion.publicada,
  String? motivo,
}) => ComentarioForo(
  id: id,
  publicacionId: publicacionId,
  autorId: autorId ?? 'autor-$id',
  autorNombre: autorNombre,
  contenido: contenido,
  fechaCreacion: fecha ?? DateTime(2026, 10, 16, 10),
  autorEsAdmin: autorEsAdmin,
  fechaEdicion: fechaEdicion,
  estado: estado,
  motivoModeracion: motivo,
);

/// Una publicación de ejemplo para las pruebas.
PublicacionForo publicacionDePrueba({
  String id = 'pub-1',
  String? autorId,
  String titulo = '¿Qué tenis para asfalto?',
  String contenido = 'Busco recomendaciones para correr 10 km.',
  String autorNombre = 'Carlos',
  EstadoPublicacion estado = EstadoPublicacion.publicada,
  DateTime? fecha,
  String? motivo,
  bool autorEsAdmin = false,
  DateTime? fechaEdicion,
}) => PublicacionForo(
  id: id,
  autorId: autorId ?? 'autor-$id',
  autorNombre: autorNombre,
  titulo: titulo,
  contenido: contenido,
  estado: estado,
  fechaCreacion: fecha ?? DateTime(2026, 10, 16, 8),
  motivoModeracion: motivo,
  autorEsAdmin: autorEsAdmin,
  fechaEdicion: fechaEdicion,
);

/// Una moderación de ejemplo para las pruebas (SCRUM-322).
ModeracionForo moderacionDePrueba({
  String id = 'mod-1',
  TipoModeracion tipo = TipoModeracion.publicacion,
  String publicacionId = 'pub-1',
  String? comentarioId,
  String autorId = ForoRepositorioFalso.usuario,
  String autorNombre = 'Ana Runner',
  AccionModeracion accion = AccionModeracion.creacion,
  String? titulo = 'Compra ya',
  String contenido = 'Descuentos en www.tenis-baratos.shop',
  EstadoModeracion estado = EstadoModeracion.rechazada,
  String? motivo = 'Spam',
  List<String> categorias = const ['Spam'],
  ResponsableModeracion? responsable = ResponsableModeracion.ia,
  String? responsableNombre = 'Moderación automática',
  DateTime? fechaSolicitud,
  DateTime? fechaDecision,
  bool vistaPorAutor = false,
}) => ModeracionForo(
  id: id,
  tipo: tipo,
  publicacionId: publicacionId,
  comentarioId: tipo == TipoModeracion.comentario
      ? (comentarioId ?? 'com-1')
      : null,
  autorId: autorId,
  autorNombre: autorNombre,
  accion: accion,
  titulo: tipo == TipoModeracion.publicacion ? titulo : null,
  contenido: contenido,
  estado: estado,
  motivo: motivo,
  categorias: categorias,
  responsable: responsable,
  responsableNombre: responsableNombre,
  fechaSolicitud: fechaSolicitud ?? DateTime(2026, 10, 16, 9),
  fechaDecision:
      fechaDecision ??
      (estado == EstadoModeracion.enRevision
          ? null
          : DateTime(2026, 10, 16, 9, 0, 7)),
  vistaPorAutor: vistaPorAutor,
);
