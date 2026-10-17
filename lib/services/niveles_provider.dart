import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nivel.dart';
import '../models/nuevo_nivel.dart';
import 'niveles_service.dart';
import 'objetivos_service.dart' show SesionRequeridaException;
import 'retos_service.dart' show SoloAdministradorException;

/// Cómo terminó un intento de crear un nivel.
///
/// Es un tipo cerrado para que la pantalla tenga que contemplar los tres
/// casos: se creó, los datos están mal, o no se pudo guardar. Cada uno se
/// muestra distinto — el primero vuelve al listado, el segundo marca campos y
/// el tercero avisa sin perder lo escrito.
sealed class ResultadoCreacionNivel {
  const ResultadoCreacionNivel();
}

/// El nivel quedó registrado. [nivel] trae el id que puso la base.
class NivelCreado extends ResultadoCreacionNivel {
  const NivelCreado(this.nivel);

  final Nivel nivel;
}

/// Los datos no pasaron las reglas (SCRUM-181).
///
/// [errores] viene por campo para poder indicar qué corregir, que es lo que
/// pide el criterio 2 de SCRUM-177.
class NivelConErrores extends ResultadoCreacionNivel {
  const NivelConErrores(this.errores);

  final Map<CampoNivel, String> errores;
}

/// Los datos estaban bien pero el guardado falló. Lo escrito sigue intacto:
/// el administrador puede reintentar sin volver a llenar el formulario.
class NivelNoGuardado extends ResultadoCreacionNivel {
  const NivelNoGuardado(this.mensaje);

  final String mensaje;
}

/// Los niveles registrados, del umbral más bajo al más alto.
///
/// `autoDispose`: se vuelve a consultar cada vez que se entra, así el nivel
/// recién creado aparece en el listado sin trucos (criterio 1 de SCRUM-177).
final catalogoNivelesProvider = FutureProvider.autoDispose<List<Nivel>>(
  (ref) => ref.watch(nivelesRepositoryProvider).listar(),
);

/// Creación de niveles (SCRUM-177).
final creacionNivelProvider = Provider<CreacionNivel>(CreacionNivel.new);

/// Une la validación del borrador con el guardado en Supabase.
///
/// Es el único camino para registrar un nivel: valida primero y solo entonces
/// escribe, así que un nivel inválido no llega nunca a la base.
class CreacionNivel {
  const CreacionNivel(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para crear niveles.';
  static const soloAdministrador = 'Solo el administrador puede crear niveles.';
  static const noSePudo = 'No se pudo crear el nivel. Inténtalo de nuevo.';
  static const datosRechazados =
      'Revisa los datos del nivel: la base no los aceptó.';
  static const nombreOcupado = 'Ya existe un nivel con ese nombre.';
  static const umbralOcupado = 'Ese umbral ya lo usa otro nivel.';

  /// Registra el nivel de [borrador] si pasa las reglas frente a los niveles
  /// [existentes].
  Future<ResultadoCreacionNivel> crear(
    BorradorNivel borrador,
    List<Nivel> existentes,
  ) async {
    final nivel = borrador.aNuevoNivel(existentes);
    if (nivel == null) {
      return NivelConErrores(borrador.erroresFrenteA(existentes));
    }

    try {
      return NivelCreado(
        await _ref.read(nivelesRepositoryProvider).crear(nivel),
      );
    } on SesionRequeridaException {
      return const NivelNoGuardado(sinSesion);
    } on SoloAdministradorException {
      return const NivelNoGuardado(soloAdministrador);
    } on NivelDuplicadoException catch (error) {
      // El listado con el que se validó ya no estaba al día: alguien registró
      // un nivel igual entre medias. Se marca el campo en vez de dar un aviso
      // suelto, para que se corrija sin perder lo escrito.
      return NivelConErrores({
        if (error.esElNombre)
          CampoNivel.nombre: nombreOcupado
        else
          CampoNivel.umbral: umbralOcupado,
      });
    } on DatosDeNivelInvalidosException catch (error) {
      // No debería pasar: el borrador valida las mismas reglas. Si ocurre, la
      // tabla y la validación de Dart se desalinearon.
      debugPrint('La base rechazó los datos del nivel: $error');
      return const NivelNoGuardado(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo crear el nivel: $error');
      return const NivelNoGuardado(noSePudo);
    }
  }
}
