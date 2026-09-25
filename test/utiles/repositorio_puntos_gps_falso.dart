import 'package:traza/models/punto_gps.dart';
import 'package:traza/services/puntos_gps_service.dart';

/// Registro de una llamada a `guardarTodos`.
typedef LoteGuardado = ({
  String entrenamientoId,
  List<PuntoGps> puntos,
  List<int> cortes,
});

/// Repositorio en memoria: anota cada lote que se le pide guardar y, si
/// la prueba lo indica, falla.
class RepositorioPuntosGpsFalso implements RepositorioPuntosGps {
  final List<LoteGuardado> lotes = [];

  /// Si es `true`, `guardarTodos` lanza [error].
  bool fallar = false;
  Object error = StateError('Supabase no disponible');

  @override
  Future<void> guardarTodos({
    required String entrenamientoId,
    required List<PuntoGps> puntos,
    List<int> cortes = const [],
  }) async {
    if (fallar) throw error;
    lotes.add((
      entrenamientoId: entrenamientoId,
      puntos: List.of(puntos),
      cortes: List.of(cortes),
    ));
  }
}
