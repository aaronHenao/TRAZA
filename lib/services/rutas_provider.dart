import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// (criterio 1). Quien la publica de verdad es quien la aprueba, y de eso se
/// entera el autor por su notificación (criterio 2).
class RutaEnRevision extends ResultadoPublicacionRuta {
  const RutaEnRevision(this.ruta);

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
/// `autoDispose`: una ruta se publica cuando el Runner Experto la aprueba, o
/// sea mientras el usuario hace otra cosa. Volver al apartado vuelve a
/// preguntar en vez de enseñar lo que había al abrir la app.
final rutasPublicadasProvider = FutureProvider.autoDispose<List<Ruta>>(
  (ref) => ref.read(rutasRepositoryProvider).publicadas(),
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
  /// que pide el criterio 1: publicar la manda a revisión.
  static const enRevision =
      'Tu ruta quedó en revisión. Te avisamos cuando se publique.';

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
      return RutaEnRevision(ruta);
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
