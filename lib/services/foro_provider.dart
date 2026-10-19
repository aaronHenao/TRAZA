import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/borrador_publicacion.dart';
import '../models/comentario_foro.dart';
import '../models/moderacion_foro.dart';
import '../models/publicacion_foro.dart';
import '../models/reporte_foro.dart';
import '../models/version_publicacion.dart';
import 'cambios_foro.dart';
import 'foro_service.dart';

/// Cómo terminó un intento de publicar en el foro (SCRUM-323).
///
/// Es un tipo cerrado para que la pantalla contemple todos los casos.
sealed class ResultadoPublicacion {
  const ResultadoPublicacion();
}

/// La publicación quedó registrada y ya se ve en el foro. Pasa con lo que
/// publica el administrador, que no pasa por la moderación.
class PublicacionCreada extends ResultadoPublicacion {
  const PublicacionCreada(this.publicacion);

  final PublicacionForo publicacion;
}

/// La publicación quedó registrada y la está revisando la moderación
/// (SCRUM-322). Aparece en el foro cuando se aprueba.
class PublicacionEnRevision extends ResultadoPublicacion {
  const PublicacionEnRevision(this.publicacion);

  final PublicacionForo publicacion;
}

/// El borrador no pasó las reglas: no se llegó a tocar la base.
///
/// [errores] viene por campo para indicar la corrección necesaria (criterio
/// 2 de SCRUM-323).
class PublicacionConErrores extends ResultadoPublicacion {
  const PublicacionConErrores(this.errores);

  final Map<CampoPublicacion, String> errores;
}

/// Los datos estaban bien pero el guardado falló. Lo escrito sigue intacto.
class PublicacionNoGuardada extends ResultadoPublicacion {
  const PublicacionNoGuardada(this.mensaje);

  final String mensaje;
}

/// Lo publicado en el foro (SCRUM-346), más lo propio que está en revisión
/// (SCRUM-322).
///
/// `autoDispose`: se vuelve a consultar cada vez que se entra, así lo que
/// otros publicaron aparece sin reiniciar la app.
final publicacionesForoProvider =
    FutureProvider.autoDispose<List<PublicacionForo>>(
      (ref) => ref.watch(foroRepositoryProvider).publicadas(),
    );

/// Qué mira el administrador en la moderación del foro (SCRUM-337).
///
/// "Publicadas" sale de las publicaciones; las demás, de `moderaciones_foro`,
/// así incluyen comentarios y ediciones.
enum VistaModeracionForo {
  publicadas(null, 'Publicadas'),
  pendientes(EstadoModeracion.pendiente, 'Pendientes'),
  enRevision(EstadoModeracion.enRevision, 'En revisión'),
  rechazadas(EstadoModeracion.rechazada, 'Rechazadas'),

  /// Lo que reportaron los corredores (SCRUM-369). Sale de `reportes_foro`.
  reportadas(null, 'Reportadas');

  const VistaModeracionForo(this.estado, this.etiqueta);

  /// El estado de la moderación que muestra, o null en "Publicadas" y
  /// "Reportadas".
  final EstadoModeracion? estado;
  final String etiqueta;
}

final vistaModeracionForoProvider =
    StateProvider.autoDispose<VistaModeracionForo>(
      (ref) => VistaModeracionForo.publicadas,
    );

/// Todas las publicaciones, para el administrador.
final moderacionForoProvider =
    FutureProvider.autoDispose<List<PublicacionForo>>(
      (ref) => ref.watch(foroRepositoryProvider).todasParaModeracion(),
    );

/// Lo publicado, para la pestaña "Publicadas" de la moderación.
final moderacionForoFiltradaProvider =
    Provider.autoDispose<AsyncValue<List<PublicacionForo>>>((ref) {
      return ref
          .watch(moderacionForoProvider)
          .whenData(
            (todas) => todas
                .where((p) => p.estado == EstadoPublicacion.publicada)
                .toList(),
          );
    });

/// Toda la moderación del foro, para el administrador (SCRUM-337).
final moderacionesAdminProvider =
    FutureProvider.autoDispose<List<ModeracionForo>>(
      (ref) => ref.watch(foroRepositoryProvider).moderaciones(),
    );

/// La moderación de la pestaña elegida.
///
/// Se filtra en memoria: cambiar de pestaña responde al instante y los
/// contadores salen de la misma consulta. No aplica a "Publicadas" ni a
/// "Reportadas", que tienen `estado` null y salen de otras consultas.
final moderacionesDeLaVistaProvider =
    Provider.autoDispose<AsyncValue<List<ModeracionForo>>>((ref) {
      final estado = ref.watch(vistaModeracionForoProvider).estado;
      return ref
          .watch(moderacionesAdminProvider)
          .whenData((todas) => todas.where((m) => m.estado == estado).toList());
    });

/// La moderación de lo que escribió el usuario de la sesión (SCRUM-322).
final misModeracionesProvider =
    FutureProvider.autoDispose<List<ModeracionForo>>(
      (ref) => ref.watch(foroRepositoryProvider).misModeraciones(),
    );

/// Lo propio que la moderación rechazó, de lo más reciente a lo más antiguo
/// ("Mis rechazados", SCRUM-339).
final misRechazadosProvider =
    Provider.autoDispose<AsyncValue<List<ModeracionForo>>>(
      (ref) => ref
          .watch(misModeracionesProvider)
          .whenData((todas) => todas.where((m) => m.rechazada).toList()),
    );

/// Cuántos rechazos no ha visto el autor: el contador del foro (criterio 5
/// de SCRUM-322). Cero mientras carga.
final rechazosSinVerProvider = Provider.autoDispose<int>(
  (ref) => switch (ref.watch(misRechazadosProvider)) {
    AsyncData(value: final lista) =>
      lista.where((m) => !m.vistaPorAutor).length,
    _ => 0,
  },
);

/// La edición propia de la publicación [publicacionId] que espera la
/// moderación, o null (SCRUM-322). Mientras exista, los demás ven la versión
/// anterior y no se ofrece editar otra vez.
final edicionAbiertaDePublicacionProvider = Provider.autoDispose
    .family<ModeracionForo?, String>((ref, publicacionId) {
      final usuario = ref.read(usuarioActualProvider)();
      final mias = ref.watch(misModeracionesProvider).valueOrNull ?? const [];
      return mias
          .where(
            (m) =>
                m.autorId == usuario &&
                m.tipo == TipoModeracion.publicacion &&
                m.esEdicion &&
                m.abierta &&
                m.publicacionId == publicacionId,
          )
          .firstOrNull;
    });

/// Los comentarios propios de [publicacionId] con una edición esperando la
/// moderación (SCRUM-322).
final comentariosConEdicionAbiertaProvider = Provider.autoDispose
    .family<Set<String>, String>((ref, publicacionId) {
      final usuario = ref.read(usuarioActualProvider)();
      final mias = ref.watch(misModeracionesProvider).valueOrNull ?? const [];
      return {
        for (final m in mias)
          if (m.autorId == usuario &&
              m.tipo == TipoModeracion.comentario &&
              m.esEdicion &&
              m.abierta &&
              m.publicacionId == publicacionId)
            m.comentarioId!,
      };
    });

final creacionPublicacionProvider = Provider<CreacionPublicacion>(
  CreacionPublicacion.new,
);

/// Une la validación del borrador con el guardado (SCRUM-343).
///
/// Es el único camino para publicar: valida primero y solo entonces escribe,
/// así que una publicación inválida no llega nunca a la base.
class CreacionPublicacion {
  const CreacionPublicacion(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para publicar en el foro.';
  static const noSePudo = 'No se pudo publicar. Inténtalo de nuevo.';
  static const datosRechazados = 'Revisa tu publicación: la base no la aceptó.';

  Future<ResultadoPublicacion> publicar(BorradorPublicacion borrador) async {
    final nueva = borrador.aNuevaPublicacion();
    if (nueva == null) return PublicacionConErrores(borrador.errores);

    try {
      final creada = await _ref.read(foroRepositoryProvider).crear(nueva);
      _ref
        ..invalidate(publicacionesForoProvider)
        ..invalidate(misModeracionesProvider)
        // El administrador también publica, desde la moderación.
        ..invalidate(moderacionForoProvider)
        ..invalidate(moderacionesAdminProvider);
      return switch (creada.estado) {
        EstadoPublicacion.publicada => PublicacionCreada(creada),
        // Recién creada solo puede estar en revisión; si la base llegara a
        // devolver otra cosa, para el autor es lo mismo: no se difundió.
        EstadoPublicacion.enRevision ||
        EstadoPublicacion.pendiente ||
        EstadoPublicacion.rechazada ||
        EstadoPublicacion.eliminada => PublicacionEnRevision(creada),
      };
    } on SesionRequeridaParaForoException {
      return const PublicacionNoGuardada(sinSesion);
    } on DatosDePublicacionInvalidosException catch (error) {
      debugPrint('La base rechazó la publicación: $error');
      return const PublicacionNoGuardada(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo publicar: $error');
      return const PublicacionNoGuardada(noSePudo);
    }
  }
}

/// Una publicación por su id, para el detalle (SCRUM-351).
///
/// Se consulta siempre y no se toma la del listado: lo que importa al abrirla
/// es cómo está ahora, porque pudo ser rechazada o eliminada después de que
/// se cargó el foro (criterio 3 de SCRUM-324).
final publicacionForoProvider = FutureProvider.autoDispose
    .family<PublicacionForo?, String>(
      (ref, id) => ref.watch(foroRepositoryProvider).publicacion(id),
    );

/// Los comentarios de una publicación, del más antiguo al más reciente.
final comentariosForoProvider = FutureProvider.autoDispose
    .family<List<ComentarioForo>, String>(
      (ref, publicacionId) =>
          ref.watch(foroRepositoryProvider).comentarios(publicacionId),
    );

/// Cómo terminó un intento de comentar (SCRUM-324).
sealed class ResultadoComentario {
  const ResultadoComentario();
}

/// El comentario quedó registrado. Si su [ComentarioForo.estado] no es
/// publicado, lo está revisando la moderación (SCRUM-322).
class ComentarioRegistrado extends ResultadoComentario {
  const ComentarioRegistrado(this.comentario);

  final ComentarioForo comentario;

  bool get enRevision => comentario.estado != EstadoPublicacion.publicada;
}

/// El texto no pasó las reglas: no se llegó a tocar la base (criterio 2).
class ComentarioInvalido extends ResultadoComentario {
  const ComentarioInvalido(this.error);

  final String error;
}

/// La publicación fue eliminada o rechazada y ya no admite comentarios
/// (criterio 3).
class PublicacionNoDisponible extends ResultadoComentario {
  const PublicacionNoDisponible();
}

/// El guardado falló por otra razón. Lo escrito sigue en la caja.
class ComentarioNoGuardado extends ResultadoComentario {
  const ComentarioNoGuardado(this.mensaje);

  final String mensaje;
}

final comentarioForoProvider = Provider<ComentarioPublicacion>(
  ComentarioPublicacion.new,
);

/// Une la validación del comentario con el guardado (SCRUM-350).
class ComentarioPublicacion {
  const ComentarioPublicacion(this._ref);

  final Ref _ref;

  static const noDisponible = 'La publicación ya no se encuentra disponible.';
  static const sinSesion = 'Inicia sesión para comentar.';
  static const noSePudo =
      'No se pudo enviar el comentario. Inténtalo de nuevo.';
  static const enRevision =
      'Tu comentario está en revisión. Los demás lo verán cuando se apruebe.';

  Future<ResultadoComentario> comentar(
    String publicacionId,
    BorradorComentario borrador,
  ) async {
    final nuevo = borrador.aNuevoComentario(publicacionId);
    if (nuevo == null) return ComentarioInvalido(borrador.error!);

    try {
      final comentario = await _ref
          .read(foroRepositoryProvider)
          .comentar(nuevo);
      _ref
        ..invalidate(comentariosForoProvider(publicacionId))
        ..invalidate(misModeracionesProvider)
        // Los listados muestran cuántos comentarios tiene cada publicación.
        ..invalidate(publicacionesForoProvider)
        ..invalidate(moderacionForoProvider);
      return ComentarioRegistrado(comentario);
    } on PublicacionNoDisponibleException {
      // Se vuelve a pedir la publicación para que el detalle pase a decir que
      // ya no está disponible, en vez de seguir ofreciendo la caja.
      _ref
        ..invalidate(publicacionForoProvider(publicacionId))
        ..invalidate(publicacionesForoProvider)
        ..invalidate(moderacionForoProvider);
      return const PublicacionNoDisponible();
    } on SesionRequeridaParaForoException {
      return const ComentarioNoGuardado(sinSesion);
    } catch (error) {
      debugPrint('No se pudo comentar: $error');
      return const ComentarioNoGuardado(noSePudo);
    }
  }
}

/// Las versiones anteriores de una publicación editada (SCRUM-355).
final versionesPublicacionProvider = FutureProvider.autoDispose
    .family<List<VersionPublicacion>, String>(
      (ref, publicacionId) =>
          ref.watch(foroRepositoryProvider).versiones(publicacionId),
    );

/// Cómo terminó un intento de editar una publicación (SCRUM-355).
sealed class ResultadoEdicion {
  const ResultadoEdicion();
}

/// Los cambios ya se ven: los hizo el administrador, que no pasa por la
/// moderación, o no había nada que cambiar.
class PublicacionEditada extends ResultadoEdicion {
  const PublicacionEditada();
}

/// Los cambios esperan la moderación (SCRUM-322). Mientras tanto, los demás
/// ven la versión anterior.
class EdicionEnRevision extends ResultadoEdicion {
  const EdicionEnRevision(this.moderacion);

  final ModeracionForo moderacion;
}

/// El borrador no pasó las reglas: no se llegó a tocar la base.
class EdicionConErrores extends ResultadoEdicion {
  const EdicionConErrores(this.errores);

  final Map<CampoPublicacion, String> errores;
}

/// La publicación fue rechazada o eliminada mientras se editaba.
class EdicionNoDisponible extends ResultadoEdicion {
  const EdicionNoDisponible();
}

/// El guardado falló por otra razón. Lo escrito sigue en el formulario.
class EdicionNoGuardada extends ResultadoEdicion {
  const EdicionNoGuardada(this.mensaje);

  final String mensaje;
}

final edicionPublicacionProvider = Provider<EdicionPublicacion>(
  EdicionPublicacion.new,
);

/// Une la validación con el guardado de los cambios (SCRUM-355). Las reglas
/// son las mismas que al publicar.
class EdicionPublicacion {
  const EdicionPublicacion(this._ref);

  final Ref _ref;

  static const noDisponible = 'La publicación ya no se encuentra disponible.';
  static const sinSesion = 'Inicia sesión para editar tu publicación.';
  static const noSePudo =
      'No se pudieron guardar los cambios. Inténtalo de '
      'nuevo.';
  static const datosRechazados = CreacionPublicacion.datosRechazados;
  static const yaEnRevision =
      'Ya tienes una edición en revisión. Espera a que se resuelva.';

  Future<ResultadoEdicion> editar(
    String publicacionId,
    BorradorPublicacion borrador,
  ) async {
    final cambios = borrador.aNuevaPublicacion();
    if (cambios == null) return EdicionConErrores(borrador.errores);

    try {
      final moderacion = await _ref
          .read(foroRepositoryProvider)
          .editar(publicacionId, cambios);
      _refrescar(publicacionId);
      if (moderacion != null && moderacion.abierta) {
        return EdicionEnRevision(moderacion);
      }
      return const PublicacionEditada();
    } on PublicacionNoDisponibleException {
      _refrescar(publicacionId);
      return const EdicionNoDisponible();
    } on EdicionYaEnRevisionException {
      _refrescar(publicacionId);
      return const EdicionNoGuardada(yaEnRevision);
    } on SesionRequeridaParaForoException {
      return const EdicionNoGuardada(sinSesion);
    } on DatosDePublicacionInvalidosException catch (error) {
      debugPrint('La base rechazó la edición: $error');
      return const EdicionNoGuardada(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo editar: $error');
      return const EdicionNoGuardada(noSePudo);
    }
  }

  /// El detalle y los dos listados muestran el título y el contenido, el
  /// historial pudo ganar una versión y la edición en revisión cambia lo que
  /// ofrece el detalle.
  void _refrescar(String publicacionId) {
    _ref
      ..invalidate(publicacionForoProvider(publicacionId))
      ..invalidate(versionesPublicacionProvider(publicacionId))
      ..invalidate(misModeracionesProvider)
      ..invalidate(publicacionesForoProvider)
      ..invalidate(moderacionForoProvider);
  }
}

/// Las versiones anteriores de un comentario editado (SCRUM-356).
final versionesComentarioProvider = FutureProvider.autoDispose
    .family<List<VersionComentario>, String>(
      (ref, comentarioId) =>
          ref.watch(foroRepositoryProvider).versionesComentario(comentarioId),
    );

/// Cómo terminó un intento de editar un comentario (SCRUM-356).
sealed class ResultadoEdicionComentario {
  const ResultadoEdicionComentario();
}

/// El cambio ya se ve: lo hizo el administrador, o no había nada que
/// cambiar.
class ComentarioEditado extends ResultadoEdicionComentario {
  const ComentarioEditado();
}

/// El cambio espera la moderación (SCRUM-322). Mientras tanto, los demás
/// leen el texto anterior.
class EdicionComentarioEnRevision extends ResultadoEdicionComentario {
  const EdicionComentarioEnRevision(this.moderacion);

  final ModeracionForo moderacion;
}

/// El texto no pasó las reglas: no se llegó a tocar la base.
class EdicionComentarioInvalida extends ResultadoEdicionComentario {
  const EdicionComentarioInvalida(this.error);

  final String error;
}

/// La publicación fue rechazada o eliminada mientras se editaba.
class EdicionComentarioNoDisponible extends ResultadoEdicionComentario {
  const EdicionComentarioNoDisponible();
}

/// El guardado falló por otra razón. Lo escrito sigue en la caja.
class EdicionComentarioNoGuardada extends ResultadoEdicionComentario {
  const EdicionComentarioNoGuardada(this.mensaje);

  final String mensaje;
}

final edicionComentarioProvider = Provider<EdicionComentario>(
  EdicionComentario.new,
);

/// Une la validación con el guardado de un comentario editado (SCRUM-356).
/// Las reglas son las mismas que al comentar.
class EdicionComentario {
  const EdicionComentario(this._ref);

  final Ref _ref;

  static const noDisponible = ComentarioPublicacion.noDisponible;
  static const noSePudo =
      'No se pudieron guardar los cambios. Inténtalo de nuevo.';
  static const yaEnRevision =
      'Ya tienes una edición de este comentario en revisión.';

  Future<ResultadoEdicionComentario> editar(
    ComentarioForo comentario,
    BorradorComentario borrador,
  ) async {
    final cambios = borrador.aNuevoComentario(comentario.publicacionId);
    if (cambios == null) return EdicionComentarioInvalida(borrador.error!);

    try {
      final moderacion = await _ref
          .read(foroRepositoryProvider)
          .editarComentario(comentario.id, cambios);
      _ref
        ..invalidate(comentariosForoProvider(comentario.publicacionId))
        ..invalidate(versionesComentarioProvider(comentario.id))
        ..invalidate(misModeracionesProvider);
      if (moderacion != null && moderacion.abierta) {
        return EdicionComentarioEnRevision(moderacion);
      }
      return const ComentarioEditado();
    } on PublicacionNoDisponibleException {
      // Como al comentar: el detalle pasa a decir que ya no está disponible.
      _ref
        ..invalidate(publicacionForoProvider(comentario.publicacionId))
        ..invalidate(publicacionesForoProvider);
      return const EdicionComentarioNoDisponible();
    } on EdicionYaEnRevisionException {
      _ref.invalidate(misModeracionesProvider);
      return const EdicionComentarioNoGuardada(yaEnRevision);
    } on SesionRequeridaParaForoException {
      return const EdicionComentarioNoGuardada(ComentarioPublicacion.sinSesion);
    } catch (error) {
      debugPrint('No se pudo editar el comentario: $error');
      return const EdicionComentarioNoGuardada(noSePudo);
    }
  }
}

/// Cómo terminó una decisión del administrador (SCRUM-337).
sealed class ResultadoDecision {
  const ResultadoDecision();
}

/// Quedó aprobada o rechazada.
class ModeracionDecidida extends ResultadoDecision {
  const ModeracionDecidida(this.moderacion);

  final ModeracionForo moderacion;
}

/// Rechazar sin motivo: el autor no sabría por qué.
class DecisionSinMotivo extends ResultadoDecision {
  const DecisionSinMotivo();
}

/// Otro (la IA u otro administrador) la resolvió primero.
class DecisionYaResuelta extends ResultadoDecision {
  const DecisionYaResuelta();
}

/// No se pudo guardar.
class DecisionNoGuardada extends ResultadoDecision {
  const DecisionNoGuardada(this.mensaje);

  final String mensaje;
}

final decisionModeracionProvider = Provider<DecisionModeracion>(
  DecisionModeracion.new,
);

/// El administrador aprueba o rechaza lo que la IA dejó pendiente
/// (SCRUM-337).
class DecisionModeracion {
  const DecisionModeracion(this._ref);

  final Ref _ref;

  static const sinMotivo = 'Escribe el motivo: es lo que leerá el autor.';
  static const yaResuelta = 'Esta moderación ya fue resuelta.';
  static const noSePudo = 'No se pudo guardar la decisión. Inténtalo de nuevo.';

  Future<ResultadoDecision> decidir(
    ModeracionForo moderacion, {
    required bool aprobar,
    String? motivo,
  }) async {
    final limpio = motivo?.trim();
    if (!aprobar && (limpio == null || limpio.isEmpty)) {
      return const DecisionSinMotivo();
    }

    try {
      final decidida = await _ref
          .read(foroRepositoryProvider)
          .decidir(
            moderacion.id,
            aprobar: aprobar,
            motivo: aprobar ? null : limpio,
          );
      return ModeracionDecidida(decidida);
    } on ModeracionYaResueltaException {
      return const DecisionYaResuelta();
    } on DatosDePublicacionInvalidosException {
      return const DecisionSinMotivo();
    } catch (error) {
      debugPrint('No se pudo decidir la moderación: $error');
      return const DecisionNoGuardada(noSePudo);
    } finally {
      // Lo que se publique o rechace cambia todas las pestañas.
      _ref
        ..invalidate(moderacionesAdminProvider)
        ..invalidate(moderacionForoProvider)
        ..invalidate(publicacionesForoProvider)
        ..invalidate(publicacionForoProvider(moderacion.publicacionId))
        ..invalidate(comentariosForoProvider(moderacion.publicacionId));
    }
  }
}

/// El autor abre "Mis rechazados": el contador del foro vuelve a cero
/// (criterio 5 de SCRUM-322). Si no se puede marcar, el contador sigue y se
/// intentará la próxima vez.
Future<void> marcarRechazosVistos(WidgetRef ref) async {
  try {
    await ref.read(foroRepositoryProvider).marcarRechazosVistos();
    ref.invalidate(misModeracionesProvider);
  } catch (error) {
    debugPrint('No se pudieron marcar los rechazos como vistos: $error');
  }
}

/// Cuánto se espera después de un aviso antes de recargar (SCRUM-357): una
/// ráfaga de cambios se resuelve con una sola consulta.
const esperaCambiosForo = Duration(milliseconds: 500);

/// Publicaciones de otros que llegaron en vivo y el foro todavía no muestra
/// (SCRUM-357).
///
/// Se guardan aparte para no mover la lista mientras se lee: el foro avisa
/// "N publicaciones nuevas" y las muestra cuando el usuario lo pide.
final publicacionesNuevasProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => const {},
);

/// El último rechazo de algo propio que llegó en vivo, para avisarlo
/// (criterio 5 de SCRUM-322). Lo consume el foro y lo vuelve a null.
final rechazoRecienteProvider = StateProvider.autoDispose<CambioForo?>(
  (ref) => null,
);

/// Escucha los cambios de todo el foro mientras el foro o la moderación están
/// abiertos (SCRUM-357).
///
/// Lo que llega solo avisa: se recargan los listados, que vuelven a pasar
/// por las policies. También recarga al volver la app a primer plano, por si
/// se perdió algo mientras estuvo en segundo plano.
final foroEnVivoProvider = Provider.autoDispose<void>((ref) {
  final usuario = ref.read(usuarioActualProvider)();

  Timer? espera;
  void recargar() {
    espera?.cancel();
    // Por el contenedor y no por `ref`: así solo se recarga el listado que
    // está en pantalla. `ref.invalidate` monta el otro en modo debug y lo
    // consulta sin que nadie lo mire.
    espera = Timer(esperaCambiosForo, () {
      ref.container
        ..invalidate(publicacionesForoProvider)
        ..invalidate(moderacionForoProvider)
        ..invalidate(moderacionesAdminProvider)
        ..invalidate(misModeracionesProvider);
    });
  }

  final suscripcion = ref.read(fuenteCambiosForoProvider).delForo().listen((
    cambio,
  ) {
    final id = cambio.id;
    // Lo que publica uno mismo ya aparece al volver del formulario.
    if (cambio.esPublicacionNueva && id != null && cambio.autorId != usuario) {
      final nuevas = ref.read(publicacionesNuevasProvider.notifier);
      nuevas.state = {...nuevas.state, id};
    }
    // SCRUM-322: la moderación rechazó algo propio.
    if (cambio.esRechazo && cambio.autorId == usuario) {
      ref.read(rechazoRecienteProvider.notifier).state = cambio;
    }
    recargar();
  });
  final ciclo = AppLifecycleListener(onResume: recargar);

  ref.onDispose(() {
    espera?.cancel();
    suscripcion.cancel();
    ciclo.dispose();
  });
});

/// Escucha una publicación y sus comentarios mientras su detalle está abierto
/// (SCRUM-357).
final publicacionEnVivoProvider = Provider.autoDispose.family<void, String>((
  ref,
  publicacionId,
) {
  Timer? esperaComentarios;
  Timer? esperaPublicacion;
  Timer? esperaModeracion;

  void recargarComentarios() {
    esperaComentarios?.cancel();
    esperaComentarios = Timer(
      esperaCambiosForo,
      () => ref.invalidate(comentariosForoProvider(publicacionId)),
    );
  }

  void recargarPublicacion() {
    esperaPublicacion?.cancel();
    esperaPublicacion = Timer(
      esperaCambiosForo,
      () => ref.invalidate(publicacionForoProvider(publicacionId)),
    );
  }

  // SCRUM-322: una edición propia pasó la moderación (o no).
  void recargarModeracion() {
    esperaModeracion?.cancel();
    esperaModeracion = Timer(
      esperaCambiosForo,
      () => ref.invalidate(misModeracionesProvider),
    );
  }

  void recargarTodo() {
    recargarComentarios();
    recargarPublicacion();
    recargarModeracion();
  }

  final suscripcion = ref
      .read(fuenteCambiosForoProvider)
      .deLaPublicacion(publicacionId)
      .listen(
        (cambio) => switch (cambio.tabla) {
          TablaForo.comentarios => recargarComentarios(),
          TablaForo.publicaciones => recargarPublicacion(),
          TablaForo.moderaciones => recargarModeracion(),
          null => recargarTodo(),
        },
      );
  final ciclo = AppLifecycleListener(onResume: recargarTodo);

  ref.onDispose(() {
    esperaComentarios?.cancel();
    esperaPublicacion?.cancel();
    esperaModeracion?.cancel();
    suscripcion.cancel();
    ciclo.dispose();
  });
});

/// Todos los reportes del foro, para la bandeja del administrador
/// (SCRUM-369).
final reportesForoProvider = FutureProvider.autoDispose<List<ReporteForo>>(
  (ref) => ref.watch(foroRepositoryProvider).reportes(),
);

/// Los reportes juntos por publicación: la pestaña "Reportadas".
final publicacionesReportadasProvider =
    Provider.autoDispose<AsyncValue<List<PublicacionReportada>>>(
      (ref) => ref
          .watch(reportesForoProvider)
          .whenData(PublicacionReportada.agrupar),
    );

/// Cómo terminó un reporte (SCRUM-369).
sealed class ResultadoReporte {
  const ResultadoReporte();
}

/// Quedó registrado y está en la bandeja del administrador.
class ReporteRecibido extends ResultadoReporte {
  const ReporteRecibido();
}

/// El usuario ya la había reportado: no se registra otro (criterio 3).
class ReporteDuplicado extends ResultadoReporte {
  const ReporteDuplicado();
}

/// Eligió "Otro" sin decir por qué: no se llegó a tocar la base.
class ReporteSinDetalle extends ResultadoReporte {
  const ReporteSinDetalle();
}

/// La publicación ya no está publicada, o es suya.
class ReporteNoDisponible extends ResultadoReporte {
  const ReporteNoDisponible();
}

/// No se pudo guardar.
class ReporteNoGuardado extends ResultadoReporte {
  const ReporteNoGuardado(this.mensaje);

  final String mensaje;
}

final reporteForoProvider = Provider<ReportePublicacion>(
  ReportePublicacion.new,
);

/// El corredor reporta una publicación ofensiva (SCRUM-369).
class ReportePublicacion {
  const ReportePublicacion(this._ref);

  final Ref _ref;

  /// Criterio 2: se confirma sin decir nada que identifique a nadie.
  static const recibido =
      'Recibimos tu reporte. El autor no sabrá quién lo envió.';
  static const duplicado = 'Ya reportaste esta publicación. Está en revisión.';
  static const sinDetalle = 'Cuéntanos por qué la reportas.';
  static const noDisponible = 'Esta publicación ya no está disponible.';
  static const noSePudo = 'No se pudo enviar el reporte. Inténtalo de nuevo.';
  static const sinSesion = 'Inicia sesión para reportar.';

  Future<ResultadoReporte> reportar(
    String publicacionId,
    MotivoReporte motivo, {
    String? detalle,
  }) async {
    final limpio = detalle?.trim();
    if (motivo == MotivoReporte.otro && (limpio == null || limpio.isEmpty)) {
      return const ReporteSinDetalle();
    }

    try {
      await _ref
          .read(foroRepositoryProvider)
          .reportar(publicacionId, motivo, detalle: limpio);
      _ref.invalidate(reportesForoProvider);
      return const ReporteRecibido();
    } on PublicacionYaReportadaException {
      return const ReporteDuplicado();
    } on PublicacionNoDisponibleException {
      // Como al comentar: el detalle pasa a decir que ya no está disponible
      // en vez de seguir ofreciendo reportarla.
      _ref
        ..invalidate(publicacionForoProvider(publicacionId))
        ..invalidate(publicacionesForoProvider);
      return const ReporteNoDisponible();
    } on SesionRequeridaParaForoException {
      return const ReporteNoGuardado(sinSesion);
    } catch (error) {
      debugPrint('No se pudo enviar el reporte: $error');
      return const ReporteNoGuardado(noSePudo);
    }
  }
}
