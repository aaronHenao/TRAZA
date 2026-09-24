import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nuevo_reto.dart';
import '../models/reto.dart';
import 'reloj_provider.dart';
import 'retos_service.dart';

/// Cómo terminó un intento de crear un reto.
///
/// Es un tipo cerrado para que la pantalla tenga que contemplar los tres
/// casos: se creó, los datos están mal, o no se pudo guardar. Cada uno se
/// muestra distinto — el primero navega, el segundo marca campos y el tercero
/// avisa sin perder lo escrito.
sealed class ResultadoCreacionReto {
  const ResultadoCreacionReto();
}

/// El reto quedó registrado. [reto] trae el id y el estado que puso la base.
class RetoCreado extends ResultadoCreacionReto {
  const RetoCreado(this.reto);

  final Reto reto;
}

/// El borrador no pasó las reglas: no se llegó a tocar la base.
///
/// [errores] viene por campo para poder señalar cuáles corregir (criterio 2
/// de SCRUM-132).
class RetoConErrores extends ResultadoCreacionReto {
  const RetoConErrores(this.errores);

  final Map<CampoReto, String> errores;
}

/// Los datos estaban bien pero el guardado falló. Lo escrito sigue intacto:
/// el administrador puede reintentar sin volver a llenar el formulario.
class RetoNoGuardado extends ResultadoCreacionReto {
  const RetoNoGuardado(this.mensaje);

  final String mensaje;
}

/// Creación de retos (SCRUM-143).
final creacionRetoProvider = Provider<CreacionReto>(CreacionReto.new);

/// Une la validación del borrador con el guardado en Supabase.
///
/// Es el único camino para registrar un reto: valida primero y solo entonces
/// escribe, así que un reto inválido no llega nunca a la base.
class CreacionReto {
  const CreacionReto(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para crear retos.';
  static const soloAdministrador = 'Solo el administrador puede crear retos.';
  static const noSePudo = 'No se pudo crear el reto. Inténtalo de nuevo.';
  static const datosRechazados =
      'Revisa los datos del reto: la base no los aceptó.';

  Future<ResultadoCreacionReto> crear(BorradorReto borrador) async {
    // La vigencia depende de cuándo se crea el reto, así que el reloj se lee
    // en este momento y no antes (SCRUM-142).
    final reto = borrador.aNuevoReto(ahora: _ref.read(relojProvider)());
    if (reto == null) return RetoConErrores(borrador.errores);

    try {
      return RetoCreado(await _ref.read(retosRepositoryProvider).crear(reto));
    } on SesionRequeridaParaRetosException {
      return const RetoNoGuardado(sinSesion);
    } on SoloAdministradorException {
      return const RetoNoGuardado(soloAdministrador);
    } on DatosDeRetoInvalidosException catch (error) {
      // No debería pasar: el borrador valida las mismas reglas. Si ocurre, la
      // tabla y la validación de Dart se desalinearon.
      debugPrint('La base rechazó los datos del reto: $error');
      return const RetoNoGuardado(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo crear el reto: $error');
      return const RetoNoGuardado(noSePudo);
    }
  }
}
