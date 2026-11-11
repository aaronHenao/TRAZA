import 'package:traza/models/dificultad.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/services/preferencias_explorar.dart';

/// Los filtros de Explorar guardados en memoria, con lo que la prueba quiera
/// tener ya en el teléfono (preferencias de Explorar, Desarrollo Móvil).
///
/// Se comporta como el teléfono: devuelve lo último que se guardó, y guardar
/// null lo borra. Anota además cada vez que la app guarda, para comprobar
/// que lo hace al elegir y al quitar un filtro.
class PreferenciasExplorarFalsa implements PreferenciasExplorar {
  PreferenciasExplorarFalsa({this.dificultadGuardada, this.distanciaGuardada});

  /// La dificultad que hay guardada ahora, o null si no hay.
  Dificultad? dificultadGuardada;

  /// El rango de distancia que hay guardado ahora, o null si no hay.
  RangoDistancia? distanciaGuardada;

  /// Cada dificultad que la app mandó guardar, en orden. Null es borrarla.
  final List<Dificultad?> dificultadesGuardadas = [];

  /// Cada rango que la app mandó guardar, en orden. Null es borrarlo.
  final List<RangoDistancia?> distanciasGuardadas = [];

  /// Si no es null, guardar lo lanza y lo guardado no cambia: un teléfono
  /// que no deja escribir.
  Object? errorAlGuardar;

  @override
  Dificultad? dificultad() => dificultadGuardada;

  @override
  RangoDistancia? distancia() => distanciaGuardada;

  @override
  Future<void> guardarDificultad(Dificultad? dificultad) async {
    dificultadesGuardadas.add(dificultad);
    final error = errorAlGuardar;
    if (error != null) throw error;
    dificultadGuardada = dificultad;
  }

  @override
  Future<void> guardarDistancia(RangoDistancia? distancia) async {
    distanciasGuardadas.add(distancia);
    final error = errorAlGuardar;
    if (error != null) throw error;
    distanciaGuardada = distancia;
  }
}
