import 'package:traza/models/recompensa.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

/// Repositorio de recompensas en memoria (SCRUM-374): anota lo que le mandan
/// y responde como lo haría la base.
///
/// Lo comparten la gestión del administrador y el catálogo del corredor, así
/// que una recompensa creada por uno aparece al consultar el otro.
class RecompensasRepositorioFalso implements RecompensasRepository {
  RecompensasRepositorioFalso({List<Recompensa> recompensas = const []})
    : recompensas = [...recompensas];

  /// Todas las recompensas registradas, disponibles o no.
  List<Recompensa> recompensas;

  /// La última recompensa que se intentó registrar.
  NuevaRecompensa? recibida;

  /// Si no es null, cualquier método lo lanza.
  Object? error;

  /// Cuántas veces se pidió el catálogo del corredor.
  var consultasCatalogo = 0;

  /// Cuántas veces se pidió la lista completa del administrador.
  var consultasTodas = 0;

  /// La recompensa a la que se le pidió cambiar los puntos la última vez
  /// (SCRUM-380). Null si nadie lo pidió.
  Recompensa? recompensaPorCambiar;

  /// Los puntos que llegaron en el último cambio. Null si no llegó ninguno:
  /// así se comprueba que una cantidad inválida ni siquiera se intentó
  /// guardar.
  int? puntosRecibidos;

  @override
  Future<Recompensa> crear(NuevaRecompensa recompensa) async {
    recibida = recompensa;
    final error = this.error;
    if (error != null) throw error;

    // Como la base: el id y la fecha los pone ella. La fecha es posterior a
    // todas las demás, para que la más reciente quede primera en `todas`.
    final creada = Recompensa(
      id: 'creada-${recompensas.length + 1}',
      nombre: recompensa.nombre,
      descripcion: recompensa.descripcion,
      puntosRequeridos: recompensa.puntosRequeridos,
      disponible: recompensa.disponible,
      fechaCreacion: _siguienteFecha(),
    );
    recompensas = [...recompensas, creada];
    return creada;
  }

  /// Lo que ve el corredor: solo lo disponible, de menos a más puntos, igual
  /// que la consulta real.
  @override
  Future<List<Recompensa>> catalogo() async {
    consultasCatalogo++;
    final error = this.error;
    if (error != null) throw error;

    return recompensas.where((r) => r.disponible).toList()
      ..sort((a, b) => a.puntosRequeridos.compareTo(b.puntosRequeridos));
  }

  /// Lo que ve el administrador: todo, de la más reciente a la más antigua.
  @override
  Future<List<Recompensa>> todas() async {
    consultasTodas++;
    final error = this.error;
    if (error != null) throw error;

    return [...recompensas]
      ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
  }

  /// Como el update de la base (SCRUM-380): solo cambian los puntos de esa
  /// recompensa, lo demás queda igual, y lo siguiente que se consulte ya trae
  /// el valor nuevo. Si hay [error], no cambia nada.
  @override
  Future<Recompensa> cambiarPuntos(Recompensa recompensa, int puntos) async {
    recompensaPorCambiar = recompensa;
    puntosRecibidos = puntos;
    final error = this.error;
    if (error != null) throw error;

    // Como la base: sin la fila, el update no toca nada (PGRST116), y el
    // check `recompensas_puntos_validos` rechaza lo que está fuera de rango.
    final guardada = recompensas
        .where((r) => r.id == recompensa.id)
        .firstOrNull;
    if (guardada == null) throw const SoloAdministradorException();
    if (puntos < 1 || puntos > maxPuntosRecompensa) {
      throw const DatosDeRecompensaInvalidosException(
        'recompensas_puntos_validos',
      );
    }
    // Lo demás sale de la fila guardada, no de lo que mandó la pantalla.
    final cambiada = Recompensa(
      id: guardada.id,
      nombre: guardada.nombre,
      descripcion: guardada.descripcion,
      puntosRequeridos: puntos,
      disponible: guardada.disponible,
      fechaCreacion: guardada.fechaCreacion,
    );
    recompensas = [
      for (final r in recompensas) r.id == recompensa.id ? cambiada : r,
    ];
    return cambiada;
  }

  DateTime _siguienteFecha() {
    if (recompensas.isEmpty) return DateTime(2026, 10, 19, 9);
    final ultima = recompensas
        .map((r) => r.fechaCreacion)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return ultima.add(const Duration(minutes: 1));
  }
}

/// Una recompensa como las que devuelve la base, con valores de sobra para
/// que cada prueba cambie solo lo que le importa.
Recompensa recompensaDePrueba({
  String id = 'recompensa-hidratacion',
  String nombre = 'Vale de hidratación',
  String descripcion = 'Una bebida isotónica en la tienda aliada.',
  int puntos = 150,
  bool disponible = true,
  DateTime? fechaCreacion,
}) => Recompensa(
  id: id,
  nombre: nombre,
  descripcion: descripcion,
  puntosRequeridos: puntos,
  disponible: disponible,
  fechaCreacion: fechaCreacion ?? DateTime(2026, 10, 1, 9),
);
