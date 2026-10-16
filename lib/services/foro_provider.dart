import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/borrador_publicacion.dart';
import '../models/publicacion_foro.dart';
import 'foro_service.dart';

/// Cómo terminó un intento de publicar en el foro (SCRUM-323).
///
/// Es un tipo cerrado para que la pantalla contemple todos los casos.
sealed class ResultadoPublicacion {
  const ResultadoPublicacion();
}

/// La publicación quedó registrada y ya se ve en el foro.
class PublicacionCreada extends ResultadoPublicacion {
  const PublicacionCreada(this.publicacion);

  final PublicacionForo publicacion;
}

/// La publicación quedó registrada pero la moderación la retuvo para
/// revisión (criterio 3 de SCRUM-323).
///
/// Hoy no ocurre: la moderación de la IA todavía no existe y toda
/// publicación nace publicada. Cuando llegue, la base devolverá el estado
/// `retenida` y la pantalla ya sabe avisarlo.
class PublicacionRetenida extends ResultadoPublicacion {
  const PublicacionRetenida(this.publicacion);

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

/// Lo publicado en el foro (SCRUM-346).
///
/// `autoDispose`: se vuelve a consultar cada vez que se entra, así lo que
/// otros publicaron aparece sin reiniciar la app.
final publicacionesForoProvider =
    FutureProvider.autoDispose<List<PublicacionForo>>(
      (ref) => ref.watch(foroRepositoryProvider).publicadas(),
    );

/// Qué publicaciones mira el administrador en la moderación del foro.
enum VistaModeracionForo {
  publicadas(EstadoPublicacion.publicada, 'Publicadas'),
  retenidas(EstadoPublicacion.retenida, 'Retenidas');

  const VistaModeracionForo(this.estado, this.etiqueta);

  final EstadoPublicacion estado;
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

/// La moderación filtrada por la vista elegida.
///
/// Se filtra en memoria: cambiar de pestaña responde al instante y los
/// contadores de las dos salen de la misma consulta.
final moderacionForoFiltradaProvider =
    Provider.autoDispose<AsyncValue<List<PublicacionForo>>>((ref) {
      final vista = ref.watch(vistaModeracionForoProvider);
      return ref
          .watch(moderacionForoProvider)
          .whenData(
            (todas) => todas.where((p) => p.estado == vista.estado).toList(),
          );
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
      _ref.invalidate(publicacionesForoProvider);
      return switch (creada.estado) {
        EstadoPublicacion.publicada => PublicacionCreada(creada),
        // Eliminada recién creada no tiene sentido; si la moderación llegara
        // a hacerlo, para el autor es lo mismo: no se difundió.
        EstadoPublicacion.retenida ||
        EstadoPublicacion.eliminada => PublicacionRetenida(creada),
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
