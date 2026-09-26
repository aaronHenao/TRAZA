import 'criterio_movimiento.dart';

/// Ritmo actual del usuario a partir de las velocidades de los últimos
/// segundos (SCRUM-116).
///
/// El ritmo promedio de toda la actividad no sirve en vivo: con el usuario
/// quieto el tiempo sigue corriendo y el número sube sin techo. Aquí solo
/// cuentan las muestras de la última [duracion], y:
///
///  - si la última muestra es de reposo, no hay ritmo (se muestra `0'00"`)
///    desde la primera lectura quieta, sin arrastrar el paso anterior;
///  - al arrancar, basta con dos muestras seguidas en movimiento: una sola
///    podría ser un pico de ruido con el usuario quieto;
///  - el ritmo es el de las muestras en movimiento, así los segundos
///    parados de antes no lo empeoran al retomar;
///  - si la última muestra tiene más de [vigencia], no hay ritmo. Una
///    lectura sin velocidad fiable no deja muestra, y sin esta regla el
///    ritmo seguía mostrando las muestras viejas mientras caducaban una a
///    una: al parar subía a saltos durante toda la [duracion] (BUG-001).
///
/// Las muestras se fechan con la hora de llegada (reloj del teléfono), no
/// con la del GPS: los dos relojes pueden ir desfasados unos segundos.
class VentanaVelocidad {
  VentanaVelocidad({
    this.duracion = const Duration(seconds: 10),
    this.vigencia = const Duration(seconds: 3),
    this.criterio = const CriterioMovimiento(),
  });

  /// Cuánto hacia atrás se tiene en cuenta.
  final Duration duracion;

  /// Antigüedad máxima de la última muestra para seguir mostrando ritmo.
  /// Llega una lectura por segundo; esto tolera perder un par.
  final Duration vigencia;

  /// Qué velocidad cuenta como movimiento.
  final CriterioMovimiento criterio;

  final List<({DateTime en, double mps})> _muestras = [];

  /// Registra que en el instante [en] el usuario iba a [mps] m/s.
  void agregar(double mps, DateTime en) {
    _muestras.add((en: en, mps: mps));
    _purgar(en);
  }

  /// Tiempo por kilómetro al paso actual, o `null` si el usuario está
  /// quieto o no hay muestras recientes.
  Duration? ritmoPorKm(DateTime ahora) {
    _purgar(ahora);
    // Hacen falta dos muestras seguidas en movimiento aunque la anterior
    // haya caducado: si no, al salir el último reposo de la ventana una
    // muestra suelta de hace segundos volvía a dar ritmo.
    if (_muestras.length < 2) return null;
    final ultima = _muestras.last;
    if (ahora.difference(ultima.en) > vigencia) return null;
    if (!criterio.esMovimiento(ultima.mps)) return null;
    if (!criterio.esMovimiento(_muestras[_muestras.length - 2].mps)) {
      return null;
    }

    var suma = 0.0;
    var cuenta = 0;
    for (final muestra in _muestras) {
      if (!criterio.esMovimiento(muestra.mps)) continue;
      suma += muestra.mps;
      cuenta++;
    }
    final mps = suma / cuenta;
    return Duration(milliseconds: (1000 / mps * 1000).round());
  }

  /// Olvida lo que ya quedó fuera de la ventana.
  void _purgar(DateTime ahora) {
    final corte = ahora.subtract(duracion);
    _muestras.removeWhere((muestra) => muestra.en.isBefore(corte));
  }

  /// Vuelve al estado inicial (nueva actividad, o reanudar tras pausa).
  void reiniciar() => _muestras.clear();
}
