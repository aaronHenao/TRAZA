import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/revision_ruta.dart';
import '../models/ruta.dart';
import 'revision_rutas_service.dart';
import 'rutas_provider.dart';

/// Las rutas que esperan a una etapa de la revisión, para su bandeja
/// (SCRUM-321).
///
/// `autoDispose`: otro revisor puede decidir mientras tanto. Volver a la
/// bandeja vuelve a preguntar en vez de enseñar lo que había al abrirla.
final rutasPorRevisarProvider = FutureProvider.autoDispose
    .family<List<Ruta>, EtapaRevision>(
      (ref, etapa) =>
          ref.read(revisionRutasRepositoryProvider).pendientes(etapa),
    );

/// Cómo terminó una decisión sobre una ruta (SCRUM-321).
///
/// Es un tipo cerrado para que la pantalla contemple todos los casos.
sealed class ResultadoRevisionRuta {
  const ResultadoRevisionRuta();
}

/// Quedó aprobada o rechazada. [ruta] trae su estado nuevo.
class RutaRevisada extends ResultadoRevisionRuta {
  const RutaRevisada(this.ruta);

  final Ruta ruta;
}

/// Rechazar sin motivo, o con uno demasiado largo: no se completa
/// (criterio 6).
class RevisionSinMotivo extends ResultadoRevisionRuta {
  const RevisionSinMotivo(this.mensaje);

  final String mensaje;
}

/// Otro revisor decidió primero.
class RevisionYaResuelta extends ResultadoRevisionRuta {
  const RevisionYaResuelta();
}

/// No se pudo guardar, o quien decide no tiene el rol de esa etapa.
class RevisionNoGuardada extends ResultadoRevisionRuta {
  const RevisionNoGuardada(this.mensaje);

  final String mensaje;
}

final decisionRevisionRutaProvider = Provider<DecisionRevisionRuta>(
  DecisionRevisionRuta.new,
);

/// El administrador o el Runner Experto aprueba o rechaza una ruta
/// (SCRUM-321).
///
/// Es el único camino de la app para decidir sobre una ruta: valida el motivo
/// antes de ir a la red y, pase lo que pase, refresca lo que la decisión
/// cambia.
class DecisionRevisionRuta {
  const DecisionRevisionRuta(this._ref);

  final Ref _ref;

  static const yaResuelta = 'Esta ruta ya fue revisada.';
  static const sinPermiso = 'No puedes revisar esta ruta.';
  static const sinSesion = 'Inicia sesión para revisar rutas.';
  static const noSePudo = 'No se pudo guardar la decisión. Inténtalo de nuevo.';

  /// Lo que se le dice al revisor cuando su decisión queda guardada.
  static String hecho(Ruta ruta) => switch (ruta.estado) {
    EstadoRuta.revisionExperto => 'Aprobada. Pasa a un Runner Experto.',
    EstadoRuta.publicada => 'Aprobada. Ya la ve toda la comunidad.',
    EstadoRuta.rechazada => 'Rechazada. Le avisamos al autor el motivo.',
    EstadoRuta.enRevision => 'Decisión guardada.',
  };

  Future<ResultadoRevisionRuta> decidir(
    Ruta ruta, {
    required bool aprobar,
    String? motivo,
  }) async {
    final limpio = motivo?.trim();
    if (!aprobar) {
      final error = errorDelMotivo(limpio);
      if (error != null) return RevisionSinMotivo(error);
    }

    try {
      final revisada = await _ref
          .read(revisionRutasRepositoryProvider)
          .decidir(ruta.id, aprobar: aprobar, motivo: aprobar ? null : limpio);
      return RutaRevisada(revisada);
    } on RutaYaRevisadaException {
      return const RevisionYaResuelta();
    } on MotivoDeRechazoInvalidoException {
      // La app valida lo mismo antes de enviar; si llega aquí, la base y
      // `errorDelMotivo` se desalinearon.
      return RevisionSinMotivo(errorDelMotivo(limpio) ?? noSePudo);
    } on RevisionNoPermitidaException {
      return const RevisionNoGuardada(sinPermiso);
    } on SesionRequeridaParaRevisarException {
      return const RevisionNoGuardada(sinSesion);
    } catch (error) {
      debugPrint('No se pudo decidir la revisión de la ruta: $error');
      return const RevisionNoGuardada(noSePudo);
    } finally {
      // Lo decidido sale de una bandeja, entra a otra o llega a la
      // comunidad.
      _ref
        ..invalidate(rutasPorRevisarProvider)
        ..invalidate(rutasPublicadasProvider)
        ..invalidate(rutaProvider(ruta.id));
    }
  }
}
