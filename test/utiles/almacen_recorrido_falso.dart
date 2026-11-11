import 'package:traza/models/punto_pendiente.dart';
import 'package:traza/models/recorrido_local.dart';
import 'package:traza/services/almacen_recorrido.dart';

/// Un motivo que la app mandó anotar en un recorrido (Drift, Desarrollo
/// Móvil).
typedef ErrorAnotado = ({
  String entrenamientoId,
  String motivo,
  bool rechazado,
});

/// Almacén del recorrido en memoria (SCRUM-292).
///
/// Se comporta como el de archivos: guarda los puntos en orden, solo
/// devuelve los que están por encima del último dado por enviado, y olvida
/// un entrenamiento cuando se le pide.
///
/// Anota además lo que recibió, para comprobar que la app escribe en disco
/// según captura y no al final.
///
/// Desde Drift (Desarrollo Móvil) anota también los motivos de lo que no se
/// pudo enviar, y como el almacén real, deja de ofrecer en [conPendientes]
/// los recorridos rechazados. No sabe de cuentas: eso se prueba con el de
/// Drift.
class AlmacenRecorridoFalso implements AlmacenRecorrido {
  /// Puntos por entrenamiento, en el orden en que llegaron.
  final Map<String, List<PuntoPendiente>> guardados = {};

  /// Hasta qué orden está en la base, por entrenamiento.
  final Map<String, int> enviadosHasta = {};

  /// Entrenamientos que se olvidaron, en orden.
  final List<String> olvidados = [];

  /// Cada motivo que la app mandó anotar, en orden, exista o no el
  /// recorrido.
  final List<ErrorAnotado> errores = [];

  /// Entrenamientos que la base rechazó: siguen guardados, pero ya no se
  /// ofrecen para reintentar.
  final Set<String> rechazados = {};

  /// Lo que emite [recorridosDeLaCuenta]. La prueba lo fija a mano.
  List<RecorridoLocal> recorridos = const [];

  /// Error que lanzan todas las operaciones, para simular un disco que no
  /// responde.
  Object? error;

  /// Error que lanza solo [registrarError], para simular que ni siquiera se
  /// pudo anotar el motivo.
  Object? errorAlRegistrar;

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
    rechazados.remove(entrenamientoId);
    olvidados.add(entrenamientoId);
  }

  @override
  Future<List<String>> conPendientes() async {
    final error = this.error;
    if (error != null) throw error;
    return guardados.keys.where((id) => !rechazados.contains(id)).toList()
      ..sort();
  }

  @override
  Future<void> registrarError(
    String entrenamientoId,
    String motivo, {
    bool rechazado = false,
  }) async {
    final error = this.error ?? errorAlRegistrar;
    if (error != null) throw error;
    errores.add((
      entrenamientoId: entrenamientoId,
      motivo: motivo,
      rechazado: rechazado,
    ));
    // Como el real: sobre un recorrido que no existe no hace nada.
    if (rechazado && guardados.containsKey(entrenamientoId)) {
      rechazados.add(entrenamientoId);
    }
  }

  @override
  Stream<List<RecorridoLocal>> recorridosDeLaCuenta() {
    final error = this.error;
    if (error != null) return Stream.error(error);
    return Stream.value(recorridos);
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
