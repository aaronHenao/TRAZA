import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dificultad.dart';
import '../models/ruta.dart';
import 'rutas_service.dart';

/// Cómo terminó un intento de publicar una ruta (SCRUM-241).
///
/// Es un tipo cerrado para que la pantalla contemple todos los casos.
sealed class ResultadoPublicacionRuta {
  const ResultadoPublicacionRuta();
}

/// La ruta quedó registrada y esperando al Runner Experto.
///
/// No hay un "RutaPublicada": publicar no publica, manda a revisión
/// (criterio 1). Cuando el experto le asigna la dificultad, el autor recibe
/// un aviso y confirma él mismo la publicación (SCRUM-363).
class RutaEnRevision extends ResultadoPublicacionRuta {
  const RutaEnRevision(this.ruta);

  final Ruta ruta;
}

/// La ruta quedó registrada, pero no tiene la distancia con la que un
/// experto la clasificaría: queda con la dificultad pendiente y no llega a
/// los expertos (criterio 3 de SCRUM-363). Lo decide la base al crearla.
class RutaSinClasificar extends ResultadoPublicacionRuta {
  const RutaSinClasificar(this.ruta);

  final Ruta ruta;
}

/// El borrador no pasó las reglas: no se llegó a tocar la base.
///
/// [errores] viene por campo para indicar la información que hace falta
/// (criterio 3).
class RutaConErrores extends ResultadoPublicacionRuta {
  const RutaConErrores(this.errores);

  final Map<CampoRuta, String> errores;
}

/// Los datos estaban bien pero no se pudo guardar. Lo escrito sigue intacto.
class RutaNoPublicada extends ResultadoPublicacionRuta {
  const RutaNoPublicada(this.mensaje);

  final String mensaje;
}

/// Las rutas que la comunidad ya puede ver, para el apartado del foro.
///
/// `autoDispose`: una ruta se publica cuando su autor confirma la dificultad
/// que le asignó un Runner Experto (SCRUM-363), o sea mientras el usuario
/// hace otra cosa. Volver al apartado vuelve a preguntar en vez de enseñar
/// lo que había al abrir la app.
final rutasPublicadasProvider = FutureProvider.autoDispose<List<Ruta>>(
  (ref) => ref.read(rutasRepositoryProvider).publicadas(),
);

/// Una ruta con su trazado, para su detalle (SCRUM-240).
final rutaProvider = FutureProvider.autoDispose.family<Ruta?, String>(
  (ref, rutaId) => ref.read(rutasRepositoryProvider).ruta(rutaId),
);

/// Une la validación del borrador con el guardado (SCRUM-241).
///
/// Es el único camino para publicar una ruta: valida primero y solo entonces
/// escribe, así que una ruta inválida no llega nunca a la base.
final publicacionRutaProvider = Provider<PublicacionRuta>(PublicacionRuta.new);

class PublicacionRuta {
  const PublicacionRuta(this._ref);

  final Ref _ref;

  /// Lo que se le dice al autor cuando su ruta queda registrada. Es el aviso
  /// que pide el criterio 1: publicar la manda a revisión de un Runner
  /// Experto (SCRUM-363).
  static const enRevision =
      'Tu ruta quedó pendiente de revisión. Un Runner Experto le asignará la '
      'dificultad.';

  /// Criterio 3 de SCRUM-363: no se pudo clasificar, pero quedó guardada.
  static const sinDatosParaClasificar =
      'No pudimos clasificar tu ruta: no tiene la distancia registrada. '
      'Quedó guardada con dificultad pendiente.';

  static const sinSesion = 'Inicia sesión para publicar tu ruta.';

  static const yaPublicada = 'Ya publicaste este entrenamiento como ruta.';

  static const noPublicable =
      'Solo puedes publicar el recorrido de tus entrenamientos terminados.';

  static const sinEntrenamiento =
      'Este entrenamiento no quedó guardado, así que no se puede publicar.';

  static const datosRechazados = 'Revisa tu ruta: la base no la aceptó.';

  static const noSePudo = 'No se pudo publicar la ruta. Inténtalo de nuevo.';

  Future<ResultadoPublicacionRuta> publicar(BorradorRuta borrador) async {
    final nueva = borrador.aNuevaRuta();
    if (nueva == null) return RutaConErrores(borrador.errores);

    try {
      final ruta = await _ref.read(rutasRepositoryProvider).crear(nueva);
      // El estado lo decide la base según los datos (0045).
      return ruta.estado == EstadoRuta.datosIncompletos
          ? RutaSinClasificar(ruta)
          : RutaEnRevision(ruta);
    } on SesionRequeridaParaRutasException {
      return const RutaNoPublicada(sinSesion);
    } on EntrenamientoYaPublicadoException {
      // El doble toque y el reintento de un envío que sí funcionó acaban
      // aquí: la ruta existe, así que no hay nada que arreglar.
      return const RutaNoPublicada(yaPublicada);
    } on EntrenamientoNoPublicableException {
      return const RutaNoPublicada(noPublicable);
    } on DatosDeRutaInvalidosException catch (error) {
      // La app valida lo mismo antes de enviar, así que esto significa que
      // la tabla y `BorradorRuta` se desalinearon.
      debugPrint('La base rechazó los datos de la ruta: $error');
      return const RutaNoPublicada(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo publicar la ruta: $error');
      return const RutaNoPublicada(noSePudo);
    }
  }

  /// La ruta que el autor ya tiene de [entrenamientoId], o null si no tiene
  /// ninguna.
  ///
  /// Si la consulta falla devuelve null y deja seguir: la barrera de verdad
  /// es el índice único de `0031`, y esto solo sirve para avisar antes de que
  /// el autor escriba. Quedarse sin formulario por un fallo de red sería
  /// peor que preguntarlo dos veces.
  Future<Ruta?> rutaDeEntrenamiento(String entrenamientoId) async {
    try {
      return await _ref
          .read(rutasRepositoryProvider)
          .rutaDeEntrenamiento(entrenamientoId);
    } catch (error) {
      debugPrint('No se pudo ver si el entrenamiento ya tenía ruta: $error');
      return null;
    }
  }
}

/// Las rutas que esperan la dificultad de un Runner Experto (SCRUM-363).
///
/// `autoDispose`: se vuelve a preguntar cada vez que se abre la bandeja, así
/// lo que clasificó otro experto ya no aparece.
final rutasPorClasificarProvider = FutureProvider.autoDispose<List<Ruta>>(
  (ref) => ref.read(rutasRepositoryProvider).porClasificar(),
);

/// Cómo terminó una clasificación (SCRUM-363).
sealed class ResultadoClasificacionRuta {
  const ResultadoClasificacionRuta();
}

/// Quedó con su dificultad, esperando a que el autor la publique.
class RutaClasificada extends ResultadoClasificacionRuta {
  const RutaClasificada(this.ruta);

  final Ruta ruta;
}

/// No se guardó. La ruta sigue como estaba.
class ClasificacionNoGuardada extends ResultadoClasificacionRuta {
  const ClasificacionNoGuardada(this.mensaje);

  final String mensaje;
}

/// Clasificación de rutas por un Runner Experto (SCRUM-363).
final clasificacionRutaProvider = Provider<ClasificacionRuta>(
  ClasificacionRuta.new,
);

/// El Runner Experto le asigna la dificultad a una ruta en revisión
/// (criterio 1 de SCRUM-363).
class ClasificacionRuta {
  const ClasificacionRuta(this._ref);

  final Ref _ref;

  static const clasificada =
      'Dificultad asignada. El autor ya puede publicarla.';
  static const sinPermiso =
      'Solo un Runner Experto puede clasificar rutas ajenas.';
  static const yaCambio = 'Esta ruta ya no está en revisión.';
  static const sinSesion = 'Inicia sesión para clasificar rutas.';
  static const noSePudo =
      'No se pudo asignar la dificultad. Inténtalo de nuevo.';

  Future<ResultadoClasificacionRuta> clasificar(
    Ruta ruta,
    Dificultad dificultad,
  ) async {
    try {
      final clasificada = await _ref
          .read(rutasRepositoryProvider)
          .clasificar(ruta, dificultad);
      // Sale de la bandeja de todos los expertos. Solo si se guardó.
      _ref
        ..invalidate(rutasPorClasificarProvider)
        ..invalidate(rutaProvider(ruta.id));
      return RutaClasificada(clasificada);
    } on SinPermisoSobreRutaException {
      return const ClasificacionNoGuardada(sinPermiso);
    } on RutaCambioDeEstadoException {
      return const ClasificacionNoGuardada(yaCambio);
    } on SesionRequeridaParaRutasException {
      return const ClasificacionNoGuardada(sinSesion);
    } catch (error) {
      debugPrint('No se pudo clasificar la ruta: $error');
      return const ClasificacionNoGuardada(noSePudo);
    }
  }
}

/// Cómo terminó la confirmación del autor (SCRUM-363).
sealed class ResultadoConfirmacionRuta {
  const ResultadoConfirmacionRuta();
}

/// Quedó publicada con la dificultad que le asignó el experto.
class RutaPublicadaConDificultad extends ResultadoConfirmacionRuta {
  const RutaPublicadaConDificultad(this.ruta);

  final Ruta ruta;
}

/// No se publicó. La ruta sigue como estaba.
class ConfirmacionNoGuardada extends ResultadoConfirmacionRuta {
  const ConfirmacionNoGuardada(this.mensaje);

  final String mensaje;
}

/// Confirmación de la publicación por el autor (SCRUM-363).
final confirmacionPublicacionRutaProvider =
    Provider<ConfirmacionPublicacionRuta>(ConfirmacionPublicacionRuta.new);

/// El autor publica su ruta ya clasificada (criterio 2 de SCRUM-363).
class ConfirmacionPublicacionRuta {
  const ConfirmacionPublicacionRuta(this._ref);

  final Ref _ref;

  static const publicada = 'Tu ruta ya está publicada con su dificultad.';
  static const sinPermiso = 'Solo el autor puede publicar su ruta.';
  static const yaCambio = 'Esta ruta ya no está esperando tu confirmación.';
  static const sinSesion = 'Inicia sesión para publicar tu ruta.';
  static const noSePudo = 'No se pudo publicar la ruta. Inténtalo de nuevo.';

  Future<ResultadoConfirmacionRuta> confirmar(Ruta ruta) async {
    try {
      final publicada = await _ref
          .read(rutasRepositoryProvider)
          .confirmarPublicacion(ruta);
      // El detalle la muestra publicada y el apartado de rutas ya la trae.
      _ref
        ..invalidate(rutaProvider(ruta.id))
        ..invalidate(rutasPublicadasProvider);
      return RutaPublicadaConDificultad(publicada);
    } on SinPermisoSobreRutaException {
      return const ConfirmacionNoGuardada(sinPermiso);
    } on RutaCambioDeEstadoException {
      return const ConfirmacionNoGuardada(yaCambio);
    } on SesionRequeridaParaRutasException {
      return const ConfirmacionNoGuardada(sinSesion);
    } catch (error) {
      debugPrint('No se pudo confirmar la publicación de la ruta: $error');
      return const ConfirmacionNoGuardada(noSePudo);
    }
  }
}
