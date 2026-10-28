import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/punto_pendiente.dart';
import 'package:traza/models/tramos.dart';
import 'package:traza/services/puntos_gps_service.dart';

/// Un lote que se le pidió guardar al repositorio.
class LoteGuardado {
  LoteGuardado({required this.entrenamientoId, required this.puntos});

  final String entrenamientoId;

  /// Los puntos del lote, ya numerados.
  final List<PuntoPendiente> puntos;

  /// Sus coordenadas, para las pruebas que solo miran el trazo.
  List<PuntoGps> get coordenadas => [for (final p in puntos) p.punto];

  /// Dónde empieza cada tramo dentro del lote, como antes se mandaban los
  /// cortes.
  List<int> get cortes => cortesDesdeTramos([for (final p in puntos) p.tramo]);

  /// Los `orden_secuencia` del lote.
  List<int> get ordenes => [for (final p in puntos) p.orden];
}

/// Repositorio en memoria: anota cada lote que se le pide guardar y, si
/// la prueba lo indica, falla.
///
/// Como la base (índice único de `0053`), descarta los puntos que ya tiene:
/// reenviar un lote no duplica nada.
class RepositorioPuntosGpsFalso implements RepositorioPuntosGps {
  /// Los lotes que entraron. Un intento que falla no está aquí.
  final List<LoteGuardado> lotes = [];

  /// Cuántas veces se intentó guardar, salieran bien o mal. Es lo que dice
  /// si la app está reintentando más de la cuenta.
  int intentos = 0;

  /// Si es `true`, `guardarLote` lanza [error].
  bool fallar = false;
  Object error = StateError('Supabase no disponible');

  /// Lo que la base acabó teniendo: por entrenamiento, los puntos por su
  /// `orden_secuencia`.
  final Map<String, Map<int, PuntoPendiente>> guardados = {};

  /// Todos los puntos de [entrenamientoId] en la base, en orden.
  List<PuntoPendiente> puntosDe(String entrenamientoId) {
    final porOrden = guardados[entrenamientoId] ?? const {};
    final ordenes = porOrden.keys.toList()..sort();
    return [for (final orden in ordenes) porOrden[orden]!];
  }

  @override
  Future<void> guardarLote({
    required String entrenamientoId,
    required List<PuntoPendiente> puntos,
  }) async {
    intentos++;
    if (fallar) throw error;
    if (puntos.isEmpty) return;

    lotes.add(
      LoteGuardado(entrenamientoId: entrenamientoId, puntos: List.of(puntos)),
    );
    final destino = guardados.putIfAbsent(entrenamientoId, () => {});
    for (final punto in puntos) {
      // `on conflict do nothing`: lo que ya estaba se queda como estaba.
      destino.putIfAbsent(punto.orden, () => punto);
    }
  }
}
