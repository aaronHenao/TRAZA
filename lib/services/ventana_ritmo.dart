import '../models/tramo_recorrido.dart';

/// Ritmo actual del usuario, medido sobre los últimos segundos de
/// recorrido en vez de sobre toda la actividad (SCRUM-116).
///
/// El ritmo promedio (tiempo total / distancia total) no sirve para
/// mostrarlo en vivo: con el usuario quieto el numerador sigue creciendo y
/// el denominador no, así que el número sube sin parar y no se parece a lo
/// que el usuario está haciendo *ahora*. Aquí solo cuentan los tramos de
/// la [duracion] más reciente; lo anterior se descarta.
///
/// El promedio de toda la actividad se sigue calculando aparte, para el
/// resumen del final.
class VentanaRitmo {
  VentanaRitmo({
    this.duracion = const Duration(seconds: 30),
    this.distanciaMinimaMetros = 20,
  });

  /// Cuánto recorrido hacia atrás se tiene en cuenta.
  final Duration duracion;

  /// Por debajo de esta distancia dentro de la ventana no hay ritmo que
  /// mostrar: serían décimas de metro dando ritmos absurdos.
  final double distanciaMinimaMetros;

  final List<TramoRecorrido> _tramos = [];

  /// Tramos que siguen dentro de la ventana, del más viejo al más nuevo.
  List<TramoRecorrido> get tramos => List.unmodifiable(_tramos);

  /// Instante del último movimiento aceptado, o `null` si no hubo ninguno.
  /// Es lo que mira el detector de reposo para auto-pausar.
  DateTime? get ultimoMovimiento => _tramos.isEmpty ? null : _tramos.last.fin;

  void agregar(TramoRecorrido tramo) {
    _tramos.add(tramo);
    _purgar(tramo.fin);
  }

  /// Tiempo por kilómetro al paso de los últimos segundos, o `null` si
  /// dentro de la ventana no hay distancia suficiente (el usuario está
  /// quieto o acaba de empezar).
  ///
  /// [ahora] entra en el cálculo a propósito: si el usuario aflojó hace
  /// diez segundos, el ritmo tiene que empeorar ya, sin esperar al
  /// siguiente punto GPS.
  Duration? ritmoPorKm(DateTime ahora) {
    _purgar(ahora);
    if (_tramos.isEmpty) return null;

    var metros = 0.0;
    for (final tramo in _tramos) {
      metros += tramo.metros;
    }
    if (metros < distanciaMinimaMetros) return null;

    // Desde que arrancó el tramo más viejo que sigue en la ventana hasta
    // ahora: así el tiempo parado dentro de la ventana también cuenta.
    final transcurrido = ahora.difference(_tramos.first.inicio);
    if (transcurrido <= Duration.zero) return null;

    final segundosPorKm = transcurrido.inMilliseconds / metros;
    return Duration(milliseconds: (segundosPorKm * 1000).round());
  }

  /// Olvida lo que ya quedó fuera de la ventana.
  void _purgar(DateTime ahora) {
    final corte = ahora.subtract(duracion);
    _tramos.removeWhere((tramo) => tramo.fin.isBefore(corte));
  }

  /// Vuelve al estado inicial (nueva actividad, o reanudar tras pausa).
  void reiniciar() => _tramos.clear();
}
