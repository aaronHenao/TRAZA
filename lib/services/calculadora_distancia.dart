import 'dart:math' as math;

import '../models/punto_gps.dart';
import 'criterio_movimiento.dart';

/// Acumula la distancia recorrida a partir de lecturas GPS consecutivas
/// (SCRUM-111 y SCRUM-116).
///
/// Lógica pura (sin plugins) para poder testearla sin dispositivo. Recibe
/// **todas** las lecturas y usa, para cada tramo, la mejor evidencia que haya:
///
///  1. **Velocidad Doppler** en esta lectura y en la anterior (y sin huecos
///     de más de [huecoMaximoVelocidad] entre las dos): suma velocidad media
///     × tiempo. No depende del error de la posición, así que no se inventa
///     distancia con el usuario quieto ni se congela con un GPS de 30-40 m
///     de error. Se compara con la lectura anterior, no con el ancla: si
///     no, unas lecturas sin velocidad al arrancar dejaban el ancla atrás y
///     todo lo demás contaba como hueco (BUG-001).
///     Si el GPS dice que el usuario está quieto, no suma nada y el ancla
///     se queda en esa lectura.
///  2. **Desplazamiento entre posiciones**, como respaldo cuando no hay
///     velocidad fiable. Un punto se descarta si su precisión es peor que
///     [precisionMaximaMetros], si se movió menos del umbral de
///     [CriterioMovimiento.umbralDesplazamiento] (jitter) o si la velocidad
///     implícita es imposible (teleport). Los descartes no mueven el ancla,
///     así que caminar despacio sí acumula.
class CalculadoraDistancia {
  CalculadoraDistancia({
    this.precisionMaximaMetros = 20,
    this.criterio = const CriterioMovimiento(),
    this.huecoMaximoVelocidad = const Duration(seconds: 5),
  });

  /// Precisión horizontal máxima para medir por posiciones, en metros. No
  /// aplica a los tramos medidos por velocidad: ahí el error de la posición
  /// no entra en la cuenta. Con lecturas peores, el umbral de jitter
  /// (2.5 × el error) superaría su tope y el ruido pasaría como avance.
  final double precisionMaximaMetros;

  /// Umbrales de reposo, de velocidad fiable y de jitter.
  final CriterioMovimiento criterio;

  /// Más allá de este tiempo entre dos lecturas no se integra la velocidad:
  /// no se sabe qué pasó en medio y se mide por posiciones.
  final Duration huecoMaximoVelocidad;

  double _distanciaMetros = 0;
  PuntoGps? _ultimoAceptado;
  double? _ultimaVelocidad;

  /// Última lectura evaluada, aceptada o no: el otro extremo del tramo que
  /// se integra por velocidad.
  PuntoGps? _anterior;

  /// Distancia acumulada en metros.
  double get distanciaMetros => _distanciaMetros;

  /// Último punto aceptado (ancla para el siguiente cálculo).
  PuntoGps? get ultimoPuntoAceptado => _ultimoAceptado;

  /// Velocidad del usuario según la última lectura evaluada, en m/s (0 si
  /// está quieto), o `null` si esa lectura no dijo nada sobre ella. Es la
  /// muestra con la que se calcula el ritmo actual.
  double? get ultimaVelocidadMps => _ultimaVelocidad;

  /// Evalúa [punto]. Devuelve `true` si se aceptó (sumara o no distancia).
  bool agregar(PuntoGps punto) {
    final velocidad = criterio.velocidadFiable(punto);
    _ultimaVelocidad = velocidad;
    final anterior = _anterior;
    _anterior = punto;

    final ancla = _ultimoAceptado;
    if (ancla == null) {
      if (velocidad == null && !_precisionAceptable(punto)) return false;
      _ultimoAceptado = punto;
      return true;
    }

    if (velocidad != null && anterior != null) {
      final dt = punto.capturadoEn.difference(anterior.capturadoEn);
      if (dt > Duration.zero && dt <= huecoMaximoVelocidad) {
        final velocidadAnterior = criterio.velocidadFiable(anterior);
        if (velocidadAnterior != null) {
          _sumar((velocidad + velocidadAnterior) / 2 * _segundos(dt), punto);
          return true;
        }
        if (velocidad == 0) {
          // Quieto según el GPS: el ancla pasa aquí sin sumar, para que el
          // jitter acumulado no se cuente después como un tramo.
          _ultimoAceptado = punto;
          return true;
        }
      }
    }

    final dt = punto.capturadoEn.difference(ancla.capturadoEn);
    // Sin tiempo transcurrido no hay tramo que medir.
    if (dt <= Duration.zero) return false;
    return _agregarPorPosicion(punto, ancla, _segundos(dt));
  }

  static double _segundos(Duration dt) =>
      dt.inMicroseconds / Duration.microsecondsPerSecond;

  bool _agregarPorPosicion(PuntoGps punto, PuntoGps ancla, double segundos) {
    if (!_precisionAceptable(punto)) return false;
    if (!_precisionAceptable(ancla)) {
      // Un ancla que entró por velocidad con mala posición no sirve para
      // medir desplazamiento: se rehace desde aquí sin sumar.
      _ultimoAceptado = punto;
      return true;
    }

    final d = haversineMetros(
      ancla.latitud,
      ancla.longitud,
      punto.latitud,
      punto.longitud,
    );
    // El umbral lo marca la peor de las dos lecturas.
    final ruido = math.max(
      ancla.precisionMetros ?? 0,
      punto.precisionMetros ?? 0,
    );
    if (d < criterio.umbralDesplazamiento(ruido)) return false;

    final velocidadImplicita = d / segundos;
    if (velocidadImplicita > criterio.velocidadMaximaMps) return false;

    _sumar(d, punto);
    _ultimaVelocidad ??= criterio.esMovimiento(velocidadImplicita)
        ? velocidadImplicita
        : 0;
    return true;
  }

  bool _precisionAceptable(PuntoGps punto) {
    final precision = punto.precisionMetros;
    return precision == null || precision <= precisionMaximaMetros;
  }

  void _sumar(double metros, PuntoGps punto) {
    _distanciaMetros += metros;
    _ultimoAceptado = punto;
  }

  /// Rompe la continuidad: el siguiente punto aceptado no suma distancia
  /// respecto al anterior. Usar al reanudar tras una pausa, para no contar
  /// lo que el usuario se movió con la actividad pausada.
  void reiniciarAncla() {
    _ultimoAceptado = null;
    _anterior = null;
  }

  /// Vuelve al estado inicial (distancia 0, sin ancla).
  void reiniciar() {
    _distanciaMetros = 0;
    _ultimoAceptado = null;
    _ultimaVelocidad = null;
    _anterior = null;
  }

  /// Radio medio de la Tierra (WGS-84), en metros.
  static const double radioTierraMetros = 6371008.8;

  /// Distancia ortodrómica entre dos coordenadas, en metros (fórmula de
  /// Haversine). Error < 0.5 % vs. el elipsoide real, sobrado para running.
  static double haversineMetros(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = _rad(lat1);
    final phi2 = _rad(lat2);
    final dPhi = _rad(lat2 - lat1);
    final dLambda = _rad(lon2 - lon1);

    final a =
        math.pow(math.sin(dPhi / 2), 2) +
        math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radioTierraMetros * c;
  }

  static double _rad(double grados) => grados * math.pi / 180;
}
