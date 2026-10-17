import 'package:traza/models/nivel.dart';
import 'package:traza/models/nuevo_nivel.dart';
import 'package:traza/services/niveles_service.dart';

/// Repositorio de niveles en memoria: responde lo que la prueba le indique y
/// anota lo que le mandaron.
class NivelesFalso implements NivelesRepository {
  NivelesFalso({this.catalogo = const []});

  /// Los niveles registrados, como los devolvería la base: del umbral más
  /// bajo al más alto.
  List<Nivel> catalogo;

  /// Si no es null, `listar` lo lanza.
  Object? errorAlListar;

  /// Si no es null, `crear` lo lanza.
  Object? errorAlCrear;

  /// El último nivel que se intentó registrar.
  NuevoNivel? recibido;

  @override
  Future<List<Nivel>> listar() async {
    final error = errorAlListar;
    if (error != null) throw error;
    return catalogo;
  }

  @override
  Future<Nivel> crear(NuevoNivel nivel) async {
    recibido = nivel;
    final error = errorAlCrear;
    if (error != null) throw error;

    // Como la base: devuelve la fila con el id que ella pone, y el listado
    // siguiente ya lo trae en su lugar.
    final creado = Nivel(
      id: 'n-${catalogo.length + 1}',
      nombre: nivel.nombre,
      umbralExperiencia: nivel.umbralExperiencia,
    );
    catalogo = [...catalogo, creado]
      ..sort((a, b) => a.umbralExperiencia.compareTo(b.umbralExperiencia));
    return creado;
  }
}
