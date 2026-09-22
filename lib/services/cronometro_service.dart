import '../models/estado_cronometro.dart';
import 'reloj_provider.dart';

export 'reloj_provider.dart' show Reloj;

/// Lógica del cronómetro de un entrenamiento (SCRUM-104).
///
/// El tiempo transcurrido **no** se acumula sumando ticks: se calcula
/// contra el reloj del sistema a partir del instante en que arrancó el
/// tramo actual. Así, si la app pasa a segundo plano y el sistema deja
/// de entregar ticks, al volver el tiempo sigue siendo el correcto.
class CronometroService {
  CronometroService({Reloj? reloj}) : _reloj = reloj ?? DateTime.now;

  final Reloj _reloj;

  /// Tiempo de los tramos ya cerrados (lo corrido antes de cada pausa).
  Duration _acumulado = Duration.zero;

  /// Instante en que arrancó el tramo en curso; `null` si no corre.
  DateTime? _inicioTramo;

  MarchaCronometro _marcha = MarchaCronometro.detenido;

  MarchaCronometro get marcha => _marcha;

  /// Tiempo total de la actividad, sin contar las pausas.
  Duration get transcurrido {
    final inicio = _inicioTramo;
    if (inicio == null) return _acumulado;

    final tramoActual = _reloj().difference(inicio);
    // Un reloj que retrocede (cambio de hora del sistema) no debe
    // restar tiempo ya contabilizado.
    if (tramoActual.isNegative) return _acumulado;

    return _acumulado + tramoActual;
  }

  EstadoCronometro get estado =>
      EstadoCronometro(transcurrido: transcurrido, marcha: _marcha);

  /// Arranca la actividad desde cero (criterio de aceptación 3).
  void iniciar() {
    _acumulado = Duration.zero;
    _inicioTramo = _reloj();
    _marcha = MarchaCronometro.enCurso;
  }

  /// Congela el tiempo transcurrido sin perderlo.
  ///
  /// Desde una auto-pausa el tiempo ya estaba congelado: solo cambia la
  /// marcha, para que el detector de reposo no lo reanude por su cuenta.
  void pausar() {
    if (_marcha == MarchaCronometro.autoPausado) {
      _marcha = MarchaCronometro.pausado;
      return;
    }
    if (_marcha != MarchaCronometro.enCurso) return;
    _cerrarTramo();
    _marcha = MarchaCronometro.pausado;
  }

  /// Retoma la cuenta desde el tiempo que ya llevaba.
  void reanudar() {
    if (_marcha != MarchaCronometro.pausado &&
        _marcha != MarchaCronometro.autoPausado) {
      return;
    }
    _inicioTramo = _reloj();
    _marcha = MarchaCronometro.enCurso;
  }

  /// Congela el tiempo porque el usuario lleva un rato quieto, sin que
  /// él lo haya pedido (SCRUM-116).
  ///
  /// Solo actúa con la actividad en curso: una pausa manual manda sobre
  /// la automática y no se toca.
  void autoPausar() {
    if (_marcha != MarchaCronometro.enCurso) return;
    _cerrarTramo();
    _marcha = MarchaCronometro.autoPausado;
  }

  /// Retoma la cuenta al detectar movimiento tras una auto-pausa.
  ///
  /// No saca de una pausa manual: esa solo la levanta el usuario.
  void autoReanudar() {
    if (_marcha != MarchaCronometro.autoPausado) return;
    _inicioTramo = _reloj();
    _marcha = MarchaCronometro.enCurso;
  }

  /// Alterna entre pausa y reanudación.
  ///
  /// Estando auto-pausado, el usuario ve el tiempo congelado y el botón
  /// en "reanudar": pulsarlo vuelve a poner el tiempo en marcha.
  void alternarPausa() {
    if (_marcha == MarchaCronometro.enCurso) {
      pausar();
    } else if (_marcha == MarchaCronometro.pausado ||
        _marcha == MarchaCronometro.autoPausado) {
      reanudar();
    }
  }

  /// Finaliza la actividad conservando el tiempo total corrido.
  void detener() {
    _cerrarTramo();
    _marcha = MarchaCronometro.detenido;
  }

  /// Vuelve todo a cero.
  void reiniciar() {
    _acumulado = Duration.zero;
    _inicioTramo = null;
    _marcha = MarchaCronometro.detenido;
  }

  void _cerrarTramo() {
    _acumulado = transcurrido;
    _inicioTramo = null;
  }
}
