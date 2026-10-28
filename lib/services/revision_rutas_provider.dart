import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/revision_ruta.dart' show errorDelMotivo;
import '../models/ruta.dart';
import 'revision_rutas_service.dart';
import 'rutas_provider.dart';

/// Las rutas que esperan al administrador, para su bandeja (SCRUM-321).
///
/// La del Runner Experto es `rutasPorClasificarProvider` (SCRUM-363).
///
/// `autoDispose`: otro revisor puede decidir mientras tanto. Volver a la
/// bandeja vuelve a preguntar en vez de enseñar lo que había al abrirla.
final rutasPorRevisarProvider = FutureProvider.autoDispose<List<Ruta>>(
  (ref) => ref.read(revisionRutasRepositoryProvider).pendientes(),
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

/// El administrador aprueba o rechaza una ruta, o el Runner Experto la
/// rechaza (SCRUM-321). Aprobar, para el experto, es asignar la dificultad:
/// `ClasificacionRuta` (SCRUM-363).
///
/// Valida el motivo antes de ir a la red y, pase lo que pase, refresca lo
/// que la decisión cambia.
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
    EstadoRuta.rechazada => 'Rechazada. Le avisamos al autor el motivo.',
    _ => 'Decisión guardada.',
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
      // Lo decidido sale de la bandeja del administrador y entra a la del
      // experto, o sale de esta.
      _ref
        ..invalidate(rutasPorRevisarProvider)
        ..invalidate(rutasPorClasificarProvider)
        ..invalidate(rutaProvider(ruta.id));
    }
  }
}
