import 'dart:math' as math;

import '../models/punto_gps.dart';

/// Reglas para decidir si una lectura del GPS es movimiento real o ruido
/// (SCRUM-116).
///
/// Las comparten el registro del recorrido y el cálculo de distancia y
/// ritmo, para que el trazo del mapa, los kilómetros y el ritmo cuenten la
/// misma historia.
///
/// La fuente preferida es la velocidad Doppler del receptor
/// ([PuntoGps.velocidadMps]): no depende del error de la posición. Con una
/// posición de 30-40 m de error (tablets, gama media, entre edificios)
/// restar coordenadas da o bien nada (si se filtra fuerte) o bien kilómetros
/// fantasma (si se filtra suave). Solo cuando no hay velocidad fiable se
/// recurre al desplazamiento entre posiciones.
class CriterioMovimiento {
  const CriterioMovimiento({
    this.velocidadReposoMps = 0.5,
    this.precisionVelocidadMaximaMps = 1.5,
    this.velocidadMaximaMps = 12.5,
    this.desplazamientoMinimoMetros = 3,
    this.desplazamientoMaximoFiltroMetros = 50,
    this.factorRuidoPrecision = 2.5,
  });

  /// Por debajo de esto el usuario está quieto (1,8 km/h). Caminar despacio
  /// ya son 0,8-1 m/s; lo que queda por debajo es ruido del receptor.
  final double velocidadReposoMps;

  /// Una velocidad con más error que esto no se usa: se recurre a las
  /// posiciones. Además, una velocidad menor que su propio error se toma
  /// como reposo (ver [velocidadFiable]).
  final double precisionVelocidadMaximaMps;

  /// Velocidad máxima plausible, en m/s. 12.5 m/s ≈ 45 km/h, muy por encima
  /// de cualquier corredor, pero por debajo de un salto de GPS.
  final double velocidadMaximaMps;

  /// Desplazamiento mínimo entre posiciones cuando la lectura es buena.
  final double desplazamientoMinimoMetros;

  /// Tope del umbral adaptativo de desplazamiento.
  final double desplazamientoMaximoFiltroMetros;

  /// Cuántas veces el error de la lectura hay que recorrer para creerse el
  /// desplazamiento. Con precisión de 8 m y factor 2.5 hacen falta 20 m.
  ///
  /// Parece mucho, pero con una lectura por segundo cualquier factor menor
  /// convierte el jitter en kilómetros: simulando 2 min quieto con el error
  /// que reporta el GPS, 0.5 inventaba 200-400 m y 1.5 más de 300 m; 2.5 no
  /// inventa nada y caminando mide con +4-12 % de error. Por eso solo es el
  /// respaldo: lo normal es medir con la velocidad Doppler.
  final double factorRuidoPrecision;

  /// La velocidad Doppler de [punto] si es fiable, o `null` si no la hay o
  /// no se puede creer. Por debajo de [velocidadReposoMps], o de su propio
  /// margen de error, devuelve 0: es un usuario quieto.
  double? velocidadFiable(PuntoGps punto) {
    final velocidad = punto.velocidadMps;
    final precision = punto.precisionVelocidadMps;
    // iOS marca con valores negativos lo que no pudo medir; Android sin
    // precisión de velocidad (API < 26) no dice cuánto creerle.
    if (velocidad == null || velocidad < 0) return null;
    if (precision == null || precision <= 0) return null;
    if (precision > precisionVelocidadMaximaMps) return null;
    if (velocidad > velocidadMaximaMps) return null;
    if (velocidad < velocidadReposoMps || velocidad < precision) return 0;
    return velocidad;
  }

  /// `true` si la velocidad cuenta como movimiento.
  bool esMovimiento(double velocidadMps) => velocidadMps >= velocidadReposoMps;

  /// Desplazamiento que hay que superar para creerse una lectura con este
  /// error ([precisionMetros]).
  ///
  /// Con señal buena es [desplazamientoMinimoMetros]; conforme empeora, sube
  /// con el propio error hasta [desplazamientoMaximoFiltroMetros].
  double umbralDesplazamiento(double? precisionMetros) {
    final porRuido = (precisionMetros ?? 0) * factorRuidoPrecision;
    return math.min(
      desplazamientoMaximoFiltroMetros,
      math.max(desplazamientoMinimoMetros, porRuido),
    );
  }
}
