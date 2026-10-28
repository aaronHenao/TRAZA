import 'package:traza/models/punto_pendiente.dart';
import 'package:traza/services/almacen_recorrido.dart';

/// Almacén del recorrido en memoria (SCRUM-292).
///
/// Se comporta como el de archivos: guarda los puntos en orden, solo
/// devuelve los que están por encima del último dado por enviado, y olvida
/// un entrenamiento cuando se le pide.
///
/// Anota además lo que recibió, para comprobar que la app escribe en disco
/// según captura y no al final.
class AlmacenRecorridoFalso implements AlmacenRecorrido {
  /// Puntos por entrenamiento, en el orden en que llegaron.
  final Map<String, List<PuntoPendiente>> guardados = {};

  /// Hasta qué orden está en la base, por entrenamiento.
  final Map<String, int> enviadosHasta = {};

  /// Entrenamientos que se olvidaron, en orden.
  final List<String> olvidados = [];

  /// Error que lanzan todas las operaciones, para simular un disco que no
  /// responde.
  Object? error;

  @override
  Future<void> anadir(String entrenamientoId, PuntoPendiente punto) async {
    final error = this.error;
    if (error != null) throw error;
    guardados.putIfAbsent(entrenamientoId, () => []).add(punto);
  }

  @override
  Future<List<PuntoPendiente>> pendientes(String entrenamientoId) async {
    final error = this.error;
    if (error != null) throw error;
    final enviados = enviadosHasta[entrenamientoId] ?? -1;
    return [
      for (final punto in guardados[entrenamientoId] ?? const [])
        if (punto.orden > enviados) punto,
    ]..sort((a, b) => a.orden.compareTo(b.orden));
  }

  @override
  Future<void> marcarEnviados(String entrenamientoId, int hastaOrden) async {
    final error = this.error;
    if (error != null) throw error;
    enviadosHasta[entrenamientoId] = hastaOrden;
  }

  @override
  Future<void> olvidar(String entrenamientoId) async {
    final error = this.error;
    if (error != null) throw error;
    guardados.remove(entrenamientoId);
    enviadosHasta.remove(entrenamientoId);
    olvidados.add(entrenamientoId);
  }

  @override
  Future<List<String>> conPendientes() async {
    final error = this.error;
    if (error != null) throw error;
    return guardados.keys.toList()..sort();
  }

  /// Simula lo que queda en disco de una sesión anterior: un recorrido a
  /// medio enviar que nadie llegó a subir.
  void sembrar(
    String entrenamientoId,
    List<PuntoPendiente> puntos, {
    int enviados = -1,
  }) {
    guardados[entrenamientoId] = [...puntos];
    if (enviados >= 0) enviadosHasta[entrenamientoId] = enviados;
  }
}

/// Un punto pendiente de ejemplo. El orden y el tramo son lo que importa en
/// casi todas las pruebas; las coordenadas se mueven con [orden] para que
/// dos puntos distintos no salgan iguales.
PuntoPendiente puntoPendienteDePrueba({
  required int orden,
  int tramo = 0,
  DateTime? capturadoEn,
}) => PuntoPendiente(
  latitud: 6.2442 + orden * 0.0001,
  longitud: -75.5812,
  capturadoEn: capturadoEn ?? DateTime(2026, 10, 27, 10, 0, orden),
  orden: orden,
  tramo: tramo,
);
