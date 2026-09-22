import 'dart:math' as math;

import '../models/punto_gps.dart';
import '../models/tramo_recorrido.dart';

/// Acumula la distancia recorrida a partir de puntos GPS consecutivos
/// (SCRUM-111).
///
/// Lógica pura (sin plugins) para poder testearla sin dispositivo. Sigue el
/// mismo enfoque que Strava / Google Maps: no se suma la distancia entre
/// *todos* los puntos que reporta el GPS, sino solo entre los que pasan un
/// filtro de ruido. Un punto se descarta si:
///
///  1. su precisión es peor que [precisionMaximaMetros] (señal mala, ej.
///     túnel);
///  2. se movió menos de [umbralPara] respecto al último punto aceptado
///     (jitter del GPS con el usuario quieto);
///  3. la velocidad implícita supera [velocidadMaximaMetrosPorSegundo]
///     (salto imposible).
///
/// Los puntos descartados no mueven el ancla, así que un usuario caminando
/// despacio sí acumula distancia: los puntos se rechazan hasta que la suma
/// del desplazamiento supera el umbral, y ahí se acepta uno.
class CalculadoraDistancia {
  CalculadoraDistancia({
    this.precisionMaximaMetros = 30,
    this.desplazamientoMinimoMetros = 3,
    this.desplazamientoMaximoFiltroMetros = 15,
    this.factorRuidoPrecision = 0.5,
    this.velocidadMaximaMetrosPorSegundo = 12.5,
  });

  /// Precisión horizontal máxima aceptada, en metros.
  ///
  /// Tiene que ser el mismo número que filtra las lecturas antes de llegar
  /// a la pantalla (`ConfiguracionRastreo.precisionMaximaMetros`): si aquí
  /// fuera más estricto, habría lecturas que mueven el marcador del mapa
  /// pero no suman distancia, y el usuario vería el punto avanzar con los
  /// kilómetros congelados (SCRUM-116).
  final double precisionMaximaMetros;

  /// Desplazamiento mínimo respecto al último punto aceptado, en metros,
  /// cuando la lectura es buena.
  final double desplazamientoMinimoMetros;

  /// Tope del umbral adaptativo. Sin él, una lectura mala exigiría tanto
  /// desplazamiento que la distancia tardaría demasiado en moverse.
  final double desplazamientoMaximoFiltroMetros;

  /// Cuánto del error de la propia lectura se exige recorrer antes de
  /// creerse el movimiento. Con precisión de 20 m y factor 0.5 hacen falta
  /// 10 m: por debajo de eso el "movimiento" puede ser solo el error.
  ///
  /// Con señal buena (5-6 m, lo normal al aire libre) no cambia nada:
  /// sale por debajo de [desplazamientoMinimoMetros]. `0` lo desactiva.
  final double factorRuidoPrecision;

  /// Velocidad máxima plausible, en m/s. 12.5 m/s ≈ 45 km/h, muy por encima
  /// de cualquier corredor, pero por debajo de un salto de GPS.
  final double velocidadMaximaMetrosPorSegundo;

  double _distanciaMetros = 0;
  PuntoGps? _ultimoAceptado;
  TramoRecorrido? _ultimoTramo;

  /// Distancia acumulada en metros.
  double get distanciaMetros => _distanciaMetros;

  /// Último punto que pasó el filtro (ancla para el siguiente cálculo).
  PuntoGps? get ultimoPuntoAceptado => _ultimoAceptado;

  /// Último trozo de recorrido que sumó distancia, o `null` si todavía no
  /// hubo ninguno. Lo consume la ventana de ritmo actual (SCRUM-116).
  TramoRecorrido? get ultimoTramo => _ultimoTramo;

  /// Desplazamiento que hay que superar para creerse una lectura con esta
  /// [precisionMetros].
  ///
  /// Con señal buena es [desplazamientoMinimoMetros]; conforme empeora,
  /// sube con el propio error de la lectura hasta
  /// [desplazamientoMaximoFiltroMetros]. Es lo que evita que, con el
  /// usuario quieto y señal regular, el ancla se vaya corriendo de lado y
  /// el siguiente tramo real se mida desde un sitio equivocado.
  double umbralPara(double? precisionMetros) {
    final porRuido = (precisionMetros ?? 0) * factorRuidoPrecision;
    return math.min(
      desplazamientoMaximoFiltroMetros,
      math.max(desplazamientoMinimoMetros, porRuido),
    );
  }

  /// Evalúa [punto]. Devuelve `true` si se aceptó y sumó distancia (o si es
  /// el primer punto / el primero tras [reiniciarAncla]).
  bool agregar(PuntoGps punto) {
    final precision = punto.precisionMetros;
    if (precision != null && precision > precisionMaximaMetros) return false;

    final ancla = _ultimoAceptado;
    if (ancla == null) {
      _ultimoAceptado = punto;
      return true;
    }

    final d = haversineMetros(
      ancla.latitud,
      ancla.longitud,
      punto.latitud,
      punto.longitud,
    );
    // El umbral lo marca la peor de las dos lecturas: si cualquiera de las
    // dos es mala, el tramo entre ellas es igual de dudoso.
    final ruido = math.max(
      ancla.precisionMetros ?? 0,
      punto.precisionMetros ?? 0,
    );
    if (d < umbralPara(ruido)) return false;

    final dt = punto.capturadoEn.difference(ancla.capturadoEn);
    // Sin tiempo transcurrido no se puede validar velocidad → se descarta.
    if (dt <= Duration.zero) return false;
    final velocidad = d / (dt.inMicroseconds / Duration.microsecondsPerSecond);
    if (velocidad > velocidadMaximaMetrosPorSegundo) return false;

    _distanciaMetros += d;
    _ultimoTramo = TramoRecorrido(
      metros: d,
      inicio: ancla.capturadoEn,
      fin: punto.capturadoEn,
    );
    _ultimoAceptado = punto;
    return true;
  }

  /// Rompe la continuidad: el siguiente punto aceptado no suma distancia
  /// respecto al anterior. Usar al reanudar tras una pausa, para no contar
  /// lo que el usuario se movió con la actividad pausada.
  void reiniciarAncla() => _ultimoAceptado = null;

  /// Vuelve al estado inicial (distancia 0, sin ancla).
  void reiniciar() {
    _distanciaMetros = 0;
    _ultimoAceptado = null;
    _ultimoTramo = null;
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
