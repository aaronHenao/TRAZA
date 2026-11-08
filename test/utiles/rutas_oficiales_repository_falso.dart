import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_oficial.dart';
import 'package:traza/services/rutas_oficiales_service.dart';

/// Repositorio de rutas oficiales en memoria (rutas oficiales, etapa 1):
/// anota lo que le piden y reacomoda el camino como lo hacen las funciones
/// de `0058_rutas_oficiales.sql`, sin huecos ni posiciones repetidas.
class RutasOficialesRepositorioFalso implements RutasOficialesRepository {
  RutasOficialesRepositorioFalso({
    List<Ruta> oficiales = const [],
    List<Ruta> rutas = const [],
  }) : enOrden = [...oficiales],
       rutas = [...rutas];

  /// Las rutas oficiales en el orden del camino: la primera es la posición 1.
  final List<Ruta> enOrden;

  /// Lo que hay en la tabla `rutas`: de aquí sale la ruta que se agrega.
  final List<Ruta> rutas;

  /// Lo que lanza `oficiales`, si algo.
  Object? errorAlListar;

  /// Lo que lanzan `agregar`, `mover` y `quitar` antes de tocar nada, si
  /// algo. Va aparte de [errorAlListar] para que un cambio pueda fallar sin
  /// que falle la lista que se vuelve a pedir después.
  Object? errorAlCambiar;

  /// Cuántas veces se pidió la lista.
  var consultas = 0;

  /// El id de cada ruta que se pidió agregar, aunque la base lo rechazara.
  final agregadas = <String>[];

  /// Cada movimiento que llegó: qué ruta y a qué posición.
  final movimientos = <(String, int)>[];

  /// El id de cada ruta que se pidió quitar. Vacío si nadie confirmó.
  final quitadas = <String>[];

  /// Los ids de las oficiales, en orden.
  List<String> get ids => [for (final ruta in enOrden) ruta.id];

  @override
  Future<List<RutaOficial>> oficiales() async {
    consultas++;
    final error = errorAlListar;
    if (error != null) throw error;

    return [
      for (final (i, ruta) in enOrden.indexed)
        RutaOficial(posicion: i + 1, ruta: ruta),
    ];
  }

  /// Como `agregar_ruta_oficial`: la ruta tiene que existir y estar
  /// publicada, no puede ser ya oficial, y queda al final.
  @override
  Future<void> agregar(String rutaId) async {
    agregadas.add(rutaId);
    _lanzarSiHayError();

    final ruta = rutas.where((r) => r.id == rutaId).firstOrNull;
    // Una que no existe (TZ404) tampoco está publicada.
    if (ruta == null || !ruta.publicada) {
      throw const RutaNoPublicadaException();
    }
    if (ids.contains(rutaId)) throw const RutaYaOficialException();
    enOrden.add(ruta);
  }

  /// Como `mover_ruta_oficial`: una posición fuera del camino se ajusta a la
  /// primera o a la última, y las demás se corren.
  @override
  Future<void> mover(String rutaId, int posicion) async {
    movimientos.add((rutaId, posicion));
    _lanzarSiHayError();

    final i = ids.indexOf(rutaId);
    // La base responde TZ404: otra pestaña ya la quitó del mapa.
    if (i < 0) throw const RutaNoOficialException();
    final ruta = enOrden.removeAt(i);
    enOrden.insert(posicion.clamp(1, enOrden.length + 1) - 1, ruta);
  }

  /// Como `quitar_ruta_oficial`: sale del camino y las de atrás suben una.
  @override
  Future<void> quitar(String rutaId) async {
    quitadas.add(rutaId);
    _lanzarSiHayError();

    if (!ids.contains(rutaId)) throw const RutaNoOficialException();
    enOrden.removeWhere((ruta) => ruta.id == rutaId);
  }

  void _lanzarSiHayError() {
    final error = errorAlCambiar;
    if (error != null) throw error;
  }
}
