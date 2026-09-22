import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/distancia_en_vivo.dart';
import '../models/estado_cronometro.dart';
import '../models/punto_gps.dart';
import 'calculadora_distancia.dart';
import 'cronometro_provider.dart';
import 'recorrido_provider.dart';
import 'ubicacion_provider.dart';
import 'ventana_ritmo.dart';

/// Cómo se construye la calculadora de cada actividad.
///
/// Toma el umbral de precisión de [configuracionRastreoProvider] para que
/// sea el mismo que filtra las lecturas antes de llegar a la pantalla: con
/// dos umbrales distintos había puntos que movían el marcador del mapa sin
/// sumar distancia (SCRUM-116). Las pruebas lo sobrescriben para ajustar
/// los umbrales del filtro.
final fabricaCalculadoraDistanciaProvider =
    Provider<CalculadoraDistancia Function()>((ref) {
  final precision = ref.watch(
    configuracionRastreoProvider.select((c) => c.precisionMaximaMetros),
  );
  return () => CalculadoraDistancia(
        precisionMaximaMetros: precision ?? double.infinity,
      );
});

/// Cómo se construye la ventana del ritmo actual. Las pruebas la
/// sobrescriben para acortar la ventana.
final fabricaVentanaRitmoProvider = Provider<VentanaRitmo Function()>(
  (ref) => VentanaRitmo.new,
);

/// Distancia recorrida y ritmo de la actividad en curso (SCRUM-111 y
/// SCRUM-112).
///
/// No abre ningún GPS propio: lee los puntos que [recorridoProvider] va
/// registrando (SCRUM-110) y los pasa por [CalculadoraDistancia], que
/// descarta el ruido y suma solo entre puntos consecutivos válidos. Al
/// reanudar tras una pausa manual se rompe la continuidad, para no contar
/// lo que el usuario se movió con la actividad pausada.
///
/// El ritmo que publica es el de los últimos segundos ([VentanaRitmo]), no
/// el promedio de toda la actividad: parado, el promedio subía sin parar
/// porque el tiempo corría y la distancia no (SCRUM-116).
///
/// Vive mientras la pantalla de entrenamiento lo observe; al salir se
/// descarta junto con el recorrido.
final distanciaProvider =
    NotifierProvider.autoDispose<DistanciaNotifier, DistanciaEnVivo>(
      DistanciaNotifier.new,
    );

class DistanciaNotifier extends AutoDisposeNotifier<DistanciaEnVivo> {
  late CalculadoraDistancia _calculadora;
  late VentanaRitmo _ventana;
  late Reloj _reloj;
  int _procesados = 0;

  @override
  DistanciaEnVivo build() {
    _calculadora = ref.watch(fabricaCalculadoraDistanciaProvider)();
    _ventana = ref.watch(fabricaVentanaRitmoProvider)();
    _reloj = ref.watch(relojProvider);
    _procesados = 0;

    ref.listen(recorridoProvider.select((recorrido) => recorrido.puntos), (
      _,
      puntos,
    ) {
      _procesar(puntos);
      state = _instantanea();
    });

    ref.listen(cronometroProvider.select((estado) => estado.marcha), (
      anterior,
      actual,
    ) {
      // Solo la pausa manual rompe la continuidad: en una auto-pausa el
      // usuario no se fue a ningún lado, así que lo que recorra al
      // arrancar de nuevo sí cuenta.
      if (anterior == MarchaCronometro.pausado &&
          actual == MarchaCronometro.enCurso) {
        _calculadora.reiniciarAncla();
        _ventana.reiniciar();
      }
    });

    // El ritmo tiene que empeorar aunque no lleguen puntos nuevos: si el
    // usuario afloja, se nota en el siguiente tick, no en el siguiente
    // fix del GPS.
    ref.listen(cronometroProvider.select((estado) => estado.transcurrido), (
      _,
      _,
    ) {
      state = _instantanea();
    });

    // Puntos registrados antes de que alguien observara la distancia.
    _procesar(ref.read(recorridoProvider).puntos);
    return _instantanea();
  }

  /// Instante del último movimiento aceptado, o `null` si no hubo ninguno
  /// en la ventana. Lo consulta el detector de reposo (SCRUM-116).
  DateTime? get ultimoMovimiento => _ventana.ultimoMovimiento;

  DistanciaEnVivo _instantanea() {
    final ritmo = _ventana.ritmoPorKm(_reloj());
    return DistanciaEnVivo(
      metros: _calculadora.distanciaMetros,
      // Al segundo entero: el ritmo se recalcula varias veces por segundo
      // y no tiene sentido que la pantalla parpadee con los milisegundos.
      ritmoActual: ritmo == null
          ? null
          : Duration(seconds: (ritmo.inMilliseconds / 1000).round()),
    );
  }

  /// Pasa por la calculadora solo los puntos que aún no se evaluaron.
  void _procesar(List<PuntoGps> puntos) {
    if (puntos.length < _procesados) {
      // El recorrido se reinició (nueva actividad).
      _calculadora.reiniciar();
      _ventana.reiniciar();
      _procesados = 0;
    }
    for (var i = _procesados; i < puntos.length; i++) {
      final antes = _calculadora.distanciaMetros;
      _calculadora.agregar(puntos[i]);
      // El primer punto se acepta sin sumar nada: no hay tramo todavía.
      if (_calculadora.distanciaMetros > antes) {
        _ventana.agregar(_calculadora.ultimoTramo!);
      }
    }
    _procesados = puntos.length;
  }
}
