import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recompensa.dart';
import 'recompensas_service.dart';
import 'retos_service.dart' show SoloAdministradorException;

/// Cómo terminó un intento de crear una recompensa (SCRUM-374).
///
/// Es un tipo cerrado para que la pantalla contemple los tres casos: se creó,
/// los datos están mal, o no se pudo guardar.
sealed class ResultadoCreacionRecompensa {
  const ResultadoCreacionRecompensa();
}

/// La recompensa quedó registrada. [recompensa] trae el id que puso la base.
class RecompensaCreada extends ResultadoCreacionRecompensa {
  const RecompensaCreada(this.recompensa);

  final Recompensa recompensa;
}

/// El borrador no pasó las reglas: no se llegó a tocar la base.
///
/// [errores] viene por campo para señalar cuáles corregir (criterio 2).
class RecompensaConErrores extends ResultadoCreacionRecompensa {
  const RecompensaConErrores(this.errores);

  final Map<CampoRecompensa, String> errores;
}

/// Los datos estaban bien pero el guardado falló. Lo escrito sigue intacto.
class RecompensaNoGuardada extends ResultadoCreacionRecompensa {
  const RecompensaNoGuardada(this.mensaje);

  final String mensaje;
}

/// Lo que ve el corredor: las recompensas disponibles con sus puntos
/// (criterio 3 de SCRUM-374).
///
/// `autoDispose`: se vuelve a consultar cada vez que se entra.
final catalogoRecompensasProvider =
    FutureProvider.autoDispose<List<Recompensa>>(
      (ref) => ref.watch(recompensasRepositoryProvider).catalogo(),
    );

/// Todas las recompensas, para la gestión del administrador.
final gestionRecompensasProvider = FutureProvider.autoDispose<List<Recompensa>>(
  (ref) => ref.watch(recompensasRepositoryProvider).todas(),
);

/// Creación de recompensas (SCRUM-374).
final creacionRecompensaProvider = Provider<CreacionRecompensa>(
  CreacionRecompensa.new,
);

/// El administrador crea una recompensa (SCRUM-374).
class CreacionRecompensa {
  const CreacionRecompensa(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para crear recompensas.';
  static const soloAdministrador =
      'Solo el administrador puede crear recompensas.';
  static const noSePudo = 'No se pudo crear la recompensa. Inténtalo de nuevo.';
  static const datosRechazados =
      'Revisa los datos de la recompensa: la base no los aceptó.';

  Future<ResultadoCreacionRecompensa> crear(BorradorRecompensa borrador) async {
    final nueva = borrador.aNuevaRecompensa();
    if (nueva == null) return RecompensaConErrores(borrador.errores);

    try {
      final creada = await _ref
          .read(recompensasRepositoryProvider)
          .crear(nueva);
      // Criterio 1: lo registrado aparece en los catálogos.
      _ref
        ..invalidate(catalogoRecompensasProvider)
        ..invalidate(gestionRecompensasProvider);
      return RecompensaCreada(creada);
    } on SesionRequeridaParaRecompensasException {
      return const RecompensaNoGuardada(sinSesion);
    } on SoloAdministradorException {
      return const RecompensaNoGuardada(soloAdministrador);
    } on DatosDeRecompensaInvalidosException catch (error) {
      // No debería pasar: el borrador valida las mismas reglas. Si ocurre, la
      // tabla y la validación de Dart se desalinearon.
      debugPrint('La base rechazó los datos de la recompensa: $error');
      return const RecompensaNoGuardada(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo crear la recompensa: $error');
      return const RecompensaNoGuardada(noSePudo);
    }
  }
}
