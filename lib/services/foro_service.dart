import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/borrador_publicacion.dart';
import '../models/comentario_foro.dart';
import '../models/moderacion_foro.dart';
import '../models/publicacion_foro.dart';
import '../models/reporte_foro.dart';
import '../models/version_publicacion.dart';

/// Repositorio del foro que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final foroRepositoryProvider = Provider<ForoRepository>(
  (ref) => SupabaseForoRepository(),
);

/// Quién usa el foro: el id del usuario con la sesión abierta, o null.
///
/// Es una función y no un valor para que siempre diga la sesión de ahora, no
/// la que había cuando se creó el provider. Las pruebas la sustituyen.
final usuarioActualProvider = Provider<String? Function()>(
  (ref) =>
      () => Supabase.instance.client.auth.currentUser?.id,
);

/// Se lanza cuando se intenta usar el foro sin una sesión abierta.
class SesionRequeridaParaForoException implements Exception {
  const SesionRequeridaParaForoException();

  @override
  String toString() =>
      'SesionRequeridaParaForoException: no hay una sesión abierta';
}

/// Se lanza cuando la base rechaza los datos de la publicación.
///
/// No debería ocurrir: `BorradorPublicacion` valida las mismas reglas antes.
/// Si llega aquí, la tabla y la validación de Dart se desalinearon.
class DatosDePublicacionInvalidosException implements Exception {
  const DatosDePublicacionInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDePublicacionInvalidosException: $detalle';
}

/// Se lanza al comentar o editar una publicación que fue eliminada o
/// rechazada por la moderación, o que todavía está en revisión (criterio 3
/// de SCRUM-324, SCRUM-355).
///
/// Quienes lo impiden son la policy de insert de `comentarios_foro` y las
/// funciones `editar_*`, que exigen que esté publicada en ese momento: la app
/// puede tener en pantalla una versión vieja.
class PublicacionNoDisponibleException implements Exception {
  const PublicacionNoDisponibleException();

  @override
  String toString() =>
      'PublicacionNoDisponibleException: la publicación ya no está publicada';
}

/// Se lanza al editar algo que ya tiene una edición en revisión (SCRUM-322):
/// hay que esperar el veredicto de la primera.
class EdicionYaEnRevisionException implements Exception {
  const EdicionYaEnRevisionException();

  @override
  String toString() =>
      'EdicionYaEnRevisionException: ya hay una edición en revisión';
}

/// Se lanza cuando el administrador decide sobre una moderación que ya se
/// resolvió: la IA respondió primero u otro administrador se adelantó.
class ModeracionYaResueltaException implements Exception {
  const ModeracionYaResueltaException();

  @override
  String toString() =>
      'ModeracionYaResueltaException: la moderación ya fue resuelta';
}

/// Se lanza cuando el usuario reporta una publicación que ya había
/// reportado (criterio 3 de SCRUM-369). Lo impide el `unique` de
/// `reportes_foro`: la publicación ya está en revisión.
class PublicacionYaReportadaException implements Exception {
  const PublicacionYaReportadaException();

  @override
  String toString() =>
      'PublicacionYaReportadaException: el usuario ya reportó la publicación';
}

/// Acceso a las tablas del foro: `publicaciones_foro` (SCRUM-323) y
/// `comentarios_foro` (SCRUM-324).
abstract interface class ForoRepository {
  /// Registra [publicacion] a nombre del usuario de la sesión y devuelve la
  /// fila creada (SCRUM-343).
  ///
  /// Lo que vuelve trae el nombre del autor, el estado y la fecha que puso la
  /// base. El estado es lo que dice si se difundió o quedó en revisión
  /// (SCRUM-322).
  Future<PublicacionForo> crear(NuevaPublicacion publicacion);

  /// Lo publicado en el foro, de lo más reciente a lo más antiguo
  /// (SCRUM-346), más lo del propio usuario que todavía espera la moderación
  /// (SCRUM-322): así ve que su publicación está "en revisión".
  Future<List<PublicacionForo>> publicadas();

  /// Todas las publicaciones, en cualquier estado, para el administrador.
  ///
  /// La policy de `select` solo le deja ver todo al administrador; a un
  /// corredor le devolvería lo publicado y lo suyo.
  Future<List<PublicacionForo>> todasParaModeracion();

  /// La publicación con [id], o null si no existe o el usuario no puede
  /// verla (SCRUM-350).
  ///
  /// Puede volver en cualquier estado: el autor ve lo suyo en revisión o
  /// rechazado, y el administrador todo. Si se puede comentar lo decide
  /// [PublicacionForo.admiteComentarios].
  Future<PublicacionForo?> publicacion(String id);

  /// Los comentarios de una publicación, del más antiguo al más reciente,
  /// como se lee una conversación (SCRUM-350).
  ///
  /// A cada uno le llegan los publicados y los suyos en cualquier estado; al
  /// administrador, todos (SCRUM-322).
  Future<List<ComentarioForo>> comentarios(String publicacionId);

  /// Registra [comentario] a nombre del usuario de la sesión y devuelve la
  /// fila creada (SCRUM-350). Lo de un corredor vuelve en revisión
  /// (SCRUM-322).
  ///
  /// Lanza [PublicacionNoDisponibleException] si la publicación ya no está
  /// publicada.
  Future<ComentarioForo> comentar(NuevoComentario comentario);

  /// Propone otro título y contenido para la publicación [id] (SCRUM-355).
  ///
  /// La edición pasa por la moderación (SCRUM-322): lo publicado no cambia
  /// hasta que se apruebe, y lo que vuelve es la moderación abierta. Si quien
  /// edita es el administrador, se aplica de una vez y vuelve aprobada.
  /// Vuelve null si el texto no cambió.
  ///
  /// Lanza [PublicacionNoDisponibleException] si no es del usuario o ya no
  /// está publicada, y [EdicionYaEnRevisionException] si ya tiene otra
  /// edición esperando.
  Future<ModeracionForo?> editar(String id, NuevaPublicacion cambios);

  /// Las versiones anteriores de una publicación editada, de la más reciente
  /// a la original (SCRUM-355). La actual no está: es la publicación misma.
  ///
  /// Solo el administrador las lee; a cualquier otro la policy le devuelve
  /// una lista vacía.
  Future<List<VersionPublicacion>> versiones(String publicacionId);

  /// Propone otro texto para el comentario [id] (SCRUM-356). Como
  /// [editar]: pasa por la moderación y vuelve la moderación abierta, o null
  /// si el texto no cambió (SCRUM-322).
  ///
  /// Lanza [PublicacionNoDisponibleException] si no es del usuario o la
  /// publicación ya no está publicada, y [EdicionYaEnRevisionException] si ya
  /// tiene otra edición esperando.
  Future<ModeracionForo?> editarComentario(String id, NuevoComentario cambios);

  /// Las versiones anteriores de un comentario editado, de la más reciente a
  /// la original (SCRUM-356). Solo el administrador las lee.
  Future<List<VersionComentario>> versionesComentario(String comentarioId);

  /// La moderación de lo que escribió el usuario de la sesión, de lo más
  /// reciente a lo más antiguo (SCRUM-322): lo que espera, lo rechazado
  /// ("Mis rechazados") y sus faltas (SCRUM-338).
  Future<List<ModeracionForo>> misModeraciones();

  /// Toda la moderación del foro, de lo más reciente a lo más antiguo, para
  /// el administrador (SCRUM-337). A un corredor la policy le devuelve solo
  /// lo suyo.
  Future<List<ModeracionForo>> moderaciones();

  /// El administrador aprueba o rechaza lo que la IA dejó pendiente
  /// (SCRUM-337). Rechazar exige [motivo]: es lo que lee el autor.
  ///
  /// Lanza [ModeracionYaResueltaException] si alguien la resolvió antes.
  Future<ModeracionForo> decidir(
    String moderacionId, {
    required bool aprobar,
    String? motivo,
  });

  /// El autor abrió "Mis rechazados": sus rechazos dejan de contarse como
  /// nuevos (criterio 5 de SCRUM-322).
  Future<void> marcarRechazosVistos();

  /// Reporta la publicación [publicacionId] a nombre del usuario de la
  /// sesión, con su [motivo] (SCRUM-369).
  ///
  /// Lanza [PublicacionYaReportadaException] si ya la había reportado y
  /// [PublicacionNoDisponibleException] si ya no está publicada o es suya.
  Future<void> reportar(
    String publicacionId,
    MotivoReporte motivo, {
    String? detalle,
  });

  /// Los últimos [SupabaseForoRepository.limiteModeracion] reportes, del más
  /// reciente al más antiguo, para la bandeja del administrador (SCRUM-369).
  /// A un corredor la policy le devuelve solo los suyos.
  Future<List<ReporteForo>> reportes();
}

class SupabaseForoRepository implements ForoRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseForoRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'publicaciones_foro';
  static const _tablaComentarios = 'comentarios_foro';
  static const _tablaVersiones = 'versiones_publicacion_foro';
  static const _tablaVersionesComentario = 'versiones_comentario_foro';
  static const _tablaModeraciones = 'moderaciones_foro';
  static const _tablaReportes = 'reportes_foro';

  /// Sin `reportante_id`: la bandeja no dice quién reportó (criterio 2 de
  /// SCRUM-369).
  static const _columnasReporte =
      'id, publicacion_id, motivo, detalle, fecha, '
      'publicaciones_foro(titulo, autor_nombre)';

  /// Las columnas de la publicación más cuántos comentarios tiene, contados
  /// por PostgREST sin traerlos. Se cuentan solo los publicados
  /// ([_soloComentariosPublicados]): los que esperan la moderación no son
  /// parte de la conversación (SCRUM-322).
  static const _columnas = '*, comentarios_foro(count)';
  static const _estadoDeLosComentarios = 'comentarios_foro.estado';

  /// Suficiente para el foro de un proyecto de curso sin traer la tabla
  /// entera.
  static const limite = 100;

  /// La moderación guarda más filas que el foro: cada edición es una.
  static const limiteModeracion = 200;

  static const _restriccionIncumplida = '23514';
  static const _rlsDenegado = '42501';

  /// La consulta pidió una fila y no vino ninguna: en un update, la policy
  /// no dejó tocar la fila.
  static const _sinFilas = 'PGRST116';

  /// La publicación ya no existe: la clave foránea no encuentra a quién
  /// apuntar.
  static const _sinReferencia = '23503';

  /// Ya hay una fila igual: el usuario ya reportó esa publicación.
  static const _repetido = '23505';

  /// Ya hay una edición en revisión, o la moderación ya se resolvió
  /// (`0035_foro_moderacion_ia.sql`).
  static const _yaEnCurso = 'TZ409';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaForoException();
    return id;
  }

  @override
  Future<PublicacionForo> crear(NuevaPublicacion publicacion) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tabla)
          // Ni el nombre del autor ni el estado van: los pone el trigger
          // `publicaciones_foro_preparar`. Si los mandara el cliente,
          // cualquiera publicaría con otro nombre o saltándose la moderación.
          .insert({...publicacion.aSupabase(), 'autor_id': usuarioId})
          .select()
          .single();

      return PublicacionForo.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<PublicacionForo>> publicadas() async {
    final usuarioId = _usuarioId();
    final esperando = [
      EstadoPublicacion.enRevision,
      EstadoPublicacion.pendiente,
    ].map((e) => e.valorDb).join(',');

    // El filtro va aunque RLS ya oculte lo ajeno: el autor también ve lo suyo
    // rechazado, y eso no pertenece al foro sino a "Mis rechazados".
    final filas = await _cliente
        .from(_tabla)
        .select(_columnas)
        .eq(_estadoDeLosComentarios, EstadoPublicacion.publicada.valorDb)
        .or(
          'estado.eq.${EstadoPublicacion.publicada.valorDb},'
          'and(autor_id.eq.$usuarioId,estado.in.($esperando))',
        )
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(PublicacionForo.desdeSupabase).toList();
  }

  @override
  Future<List<PublicacionForo>> todasParaModeracion() async {
    _usuarioId();

    final filas = await _cliente
        .from(_tabla)
        .select(_columnas)
        .eq(_estadoDeLosComentarios, EstadoPublicacion.publicada.valorDb)
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(PublicacionForo.desdeSupabase).toList();
  }

  @override
  Future<PublicacionForo?> publicacion(String id) async {
    _usuarioId();

    final fila = await _cliente
        .from(_tabla)
        .select(_columnas)
        .eq('id', id)
        .eq(_estadoDeLosComentarios, EstadoPublicacion.publicada.valorDb)
        .maybeSingle();

    return fila == null ? null : PublicacionForo.desdeSupabase(fila);
  }

  @override
  Future<List<ComentarioForo>> comentarios(String publicacionId) async {
    _usuarioId();

    final filas = await _cliente
        .from(_tablaComentarios)
        .select()
        .eq('publicacion_id', publicacionId)
        .order('fecha_creacion', ascending: true)
        .limit(limite);

    return filas.map(ComentarioForo.desdeSupabase).toList();
  }

  @override
  Future<ComentarioForo> comentar(NuevoComentario comentario) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tablaComentarios)
          // Ni el nombre del autor ni el estado van: los pone el trigger.
          .insert({...comentario.aSupabase(), 'autor_id': usuarioId})
          .select()
          .single();

      return ComentarioForo.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // La policy de insert exige que la publicación siga publicada; si fue
      // rechazada o eliminada, la fila viola la seguridad a nivel de fila.
      if (e.code == _rlsDenegado || e.code == _sinReferencia) {
        throw const PublicacionNoDisponibleException();
      }
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<VersionPublicacion>> versiones(String publicacionId) async {
    _usuarioId();

    final filas = await _cliente
        .from(_tablaVersiones)
        .select()
        .eq('publicacion_id', publicacionId)
        .order('reemplazada_en', ascending: false)
        .limit(limite);

    return filas.map(VersionPublicacion.desdeSupabase).toList();
  }

  @override
  Future<ModeracionForo?> editar(String id, NuevaPublicacion cambios) {
    _usuarioId();

    // Por la función y no con un update: la fila visible no cambia hasta
    // que se apruebe, y lo propuesto espera en `moderaciones_foro`.
    return _proponerEdicion('editar_publicacion_foro', {
      'p_id': id,
      'p_titulo': cambios.titulo,
      'p_contenido': cambios.contenido,
    });
  }

  @override
  Future<ModeracionForo?> editarComentario(String id, NuevoComentario cambios) {
    _usuarioId();

    return _proponerEdicion('editar_comentario_foro', {
      'p_id': id,
      'p_contenido': cambios.contenido,
    });
  }

  Future<ModeracionForo?> _proponerEdicion(
    String funcion,
    Map<String, dynamic> parametros,
  ) async {
    try {
      final respuesta = await _cliente.rpc(funcion, params: parametros);
      return _moderacionDe(respuesta);
    } on PostgrestException catch (e) {
      // No es suyo o ya no está publicado.
      if (e.code == _rlsDenegado || e.code == _sinFilas) {
        throw const PublicacionNoDisponibleException();
      }
      if (e.code == _yaEnCurso) throw const EdicionYaEnRevisionException();
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }

  /// La fila que devuelve una función de la moderación, o null.
  ///
  /// Las funciones devuelven una fila de `moderaciones_foro`; cuando la
  /// función devuelve null, PostgREST manda null o la fila con todo en null,
  /// según la versión.
  static ModeracionForo? _moderacionDe(Object? respuesta) {
    final fila = switch (respuesta) {
      [final Map<String, dynamic> primera, ...] => primera,
      final Map<String, dynamic> unica => unica,
      _ => null,
    };
    if (fila == null || fila['id'] == null) return null;
    return ModeracionForo.desdeSupabase(fila);
  }

  @override
  Future<List<VersionComentario>> versionesComentario(
    String comentarioId,
  ) async {
    _usuarioId();

    final filas = await _cliente
        .from(_tablaVersionesComentario)
        .select()
        .eq('comentario_id', comentarioId)
        .order('reemplazada_en', ascending: false)
        .limit(limite);

    return filas.map(VersionComentario.desdeSupabase).toList();
  }

  @override
  Future<List<ModeracionForo>> misModeraciones() async {
    final usuarioId = _usuarioId();

    // El filtro va aunque RLS ya lo limite: el administrador ve la de todos.
    final filas = await _cliente
        .from(_tablaModeraciones)
        .select()
        .eq('autor_id', usuarioId)
        .order('fecha_solicitud', ascending: false)
        .limit(limiteModeracion);

    return filas.map(ModeracionForo.desdeSupabase).toList();
  }

  @override
  Future<List<ModeracionForo>> moderaciones() async {
    _usuarioId();

    final filas = await _cliente
        .from(_tablaModeraciones)
        .select()
        .order('fecha_solicitud', ascending: false)
        .limit(limiteModeracion);

    return filas.map(ModeracionForo.desdeSupabase).toList();
  }

  @override
  Future<ModeracionForo> decidir(
    String moderacionId, {
    required bool aprobar,
    String? motivo,
  }) async {
    _usuarioId();

    try {
      final respuesta = await _cliente.rpc(
        'decidir_moderacion',
        params: {
          'p_moderacion_id': moderacionId,
          'p_aprobar': aprobar,
          'p_motivo': motivo,
        },
      );
      final decidida = _moderacionDe(respuesta);
      if (decidida == null) throw const ModeracionYaResueltaException();
      return decidida;
    } on PostgrestException catch (e) {
      if (e.code == _yaEnCurso) throw const ModeracionYaResueltaException();
      if (e.code == _restriccionIncumplida) {
        throw DatosDePublicacionInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<void> marcarRechazosVistos() async {
    _usuarioId();
    await _cliente.rpc('marcar_rechazos_vistos');
  }

  @override
  Future<void> reportar(
    String publicacionId,
    MotivoReporte motivo, {
    String? detalle,
  }) async {
    final usuarioId = _usuarioId();
    final limpio = detalle?.trim();

    try {
      // Sin `select`: lo que vuelve no hace falta.
      await _cliente.from(_tablaReportes).insert({
        'publicacion_id': publicacionId,
        'reportante_id': usuarioId,
        'motivo': motivo.valorDb,
        'detalle': (limpio == null || limpio.isEmpty) ? null : limpio,
      });
    } on PostgrestException catch (e) {
      if (e.code == _repetido) throw const PublicacionYaReportadaException();
      // La policy de insert exige que siga publicada y sea ajena; si la
      // borraron, la clave foránea no la encuentra.
      if (e.code == _rlsDenegado || e.code == _sinReferencia) {
        throw const PublicacionNoDisponibleException();
      }
      rethrow;
    }
  }

  @override
  Future<List<ReporteForo>> reportes() async {
    _usuarioId();

    final filas = await _cliente
        .from(_tablaReportes)
        .select(_columnasReporte)
        .order('fecha', ascending: false)
        .limit(limiteModeracion);

    return filas.map(ReporteForo.desdeSupabase).toList();
  }
}
