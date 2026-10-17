import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/version_publicacion.dart';
import 'package:traza/services/foro_service.dart';

/// Doble de `ForoRepository` con el foro en memoria.
///
/// Anota lo que recibe, lanza [error] si se le indica y crea las
/// publicaciones con el [estadoAlCrear] que la prueba quiera simular que puso
/// la base.
class ForoRepositorioFalso implements ForoRepository {
  ForoRepositorioFalso({
    List<PublicacionForo>? publicaciones,
    this.estadoAlCrear = EstadoPublicacion.publicada,
    this.ahora,
  }) : publicaciones = [...?publicaciones];

  final List<PublicacionForo> publicaciones;
  EstadoPublicacion estadoAlCrear;
  DateTime? ahora;

  Object? error;
  NuevaPublicacion? recibida;
  int consultas = 0;

  @override
  Future<PublicacionForo> crear(NuevaPublicacion publicacion) async {
    recibida = publicacion;
    final error = this.error;
    if (error != null) throw error;

    final creada = PublicacionForo(
      id: 'pub-${publicaciones.length + 1}',
      autorId: 'usuario-1',
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
    return publicaciones
        .where((p) => p.estado == EstadoPublicacion.publicada)
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

  /// Simula que quien publica o comenta es el administrador: la base le pone
  /// `autor_es_admin`.
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
      autorId: 'usuario-1',
      autorNombre: 'Ana Runner',
      contenido: comentario.contenido,
      fechaCreacion: ahora ?? DateTime(2026, 10, 16, 9),
      autorEsAdmin: comoAdmin,
    );
    lista.add(creado);
    return creado;
  }

  NuevaPublicacion? edicionRecibida;

  /// Error que lanza solo `editar`.
  Object? errorAlEditar;

  @override
  Future<PublicacionForo> editar(String id, NuevaPublicacion cambios) async {
    edicionRecibida = cambios;
    final error = errorAlEditar ?? this.error;
    if (error != null) throw error;

    final i = publicaciones.indexWhere((p) => p.id == id);
    if (i < 0 || publicaciones[i].estado != EstadoPublicacion.publicada) {
      throw const PublicacionNoDisponibleException();
    }
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
    return publicaciones[i] = PublicacionForo(
      id: p.id,
      autorId: p.autorId,
      autorNombre: p.autorNombre,
      titulo: cambios.titulo,
      contenido: cambios.contenido,
      estado: p.estado,
      fechaCreacion: p.fechaCreacion,
      autorEsAdmin: p.autorEsAdmin,
      fechaEdicion: ahora ?? DateTime(2026, 10, 16, 12),
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
  Future<ComentarioForo> editarComentario(
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
      return lista[i] = ComentarioForo(
        id: c.id,
        publicacionId: c.publicacionId,
        autorId: c.autorId,
        autorNombre: c.autorNombre,
        contenido: cambios.contenido,
        fechaCreacion: c.fechaCreacion,
        autorEsAdmin: c.autorEsAdmin,
        fechaEdicion: ahora ?? DateTime(2026, 10, 16, 12),
      );
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

  /// Simula que la moderación retiró la publicación [id].
  void retener(String id) {
    final i = publicaciones.indexWhere((p) => p.id == id);
    final p = publicaciones[i];
    publicaciones[i] = PublicacionForo(
      id: p.id,
      autorId: p.autorId,
      autorNombre: p.autorNombre,
      titulo: p.titulo,
      contenido: p.contenido,
      estado: EstadoPublicacion.retenida,
      fechaCreacion: p.fechaCreacion,
      autorEsAdmin: p.autorEsAdmin,
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
}) => ComentarioForo(
  id: id,
  publicacionId: publicacionId,
  autorId: autorId ?? 'autor-$id',
  autorNombre: autorNombre,
  contenido: contenido,
  fechaCreacion: fecha ?? DateTime(2026, 10, 16, 10),
  autorEsAdmin: autorEsAdmin,
  fechaEdicion: fechaEdicion,
);

/// Una publicación de ejemplo para las pruebas.
PublicacionForo publicacionDePrueba({
  String id = 'pub-1',
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
  autorId: 'autor-$id',
  autorNombre: autorNombre,
  titulo: titulo,
  contenido: contenido,
  estado: estado,
  fechaCreacion: fecha ?? DateTime(2026, 10, 16, 8),
  motivoModeracion: motivo,
  autorEsAdmin: autorEsAdmin,
  fechaEdicion: fechaEdicion,
);
