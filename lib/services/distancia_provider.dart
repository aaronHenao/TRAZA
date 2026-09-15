import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/distancia_en_vivo.dart';
import '../models/estado_cronometro.dart';
import '../models/punto_gps.dart';
import 'calculadora_distancia.dart';
import 'cronometro_provider.dart';
import 'recorrido_provider.dart';

/// Cómo se construye la calculadora de cada actividad. Las pruebas la
/// sobrescriben para ajustar los umbrales del filtro.
final fabricaCalculadoraDistanciaProvider =
    Provider<CalculadoraDistancia Function()>(
      (ref) => CalculadoraDistancia.new,
    );

/// Distancia recorrida en la actividad en curso (SCRUM-111 y SCRUM-112).
///
/// No abre ningún GPS propio: lee los puntos que [recorridoProvider] va
/// registrando (SCRUM-110) y los pasa por [CalculadoraDistancia], que
/// descarta el ruido y suma solo entre puntos consecutivos válidos. Al
/// reanudar tras una pausa se rompe la continuidad, para no contar lo que
/// el usuario se movió con la actividad pausada.
///
/// Vive mientras la pantalla de entrenamiento lo observe; al salir se
/// descarta junto con el recorrido.
final distanciaProvider =
    NotifierProvider.autoDispose<DistanciaNotifier, DistanciaEnVivo>(
      DistanciaNotifier.new,
    );

class DistanciaNotifier extends AutoDisposeNotifier<DistanciaEnVivo> {
  late CalculadoraDistancia _calculadora;
  int _procesados = 0;

  @override
  DistanciaEnVivo build() {
    _calculadora = ref.watch(fabricaCalculadoraDistanciaProvider)();
    _procesados = 0;

    ref.listen(recorridoProvider.select((recorrido) => recorrido.puntos), (
      _,
      puntos,
    ) {
      _procesar(puntos);
      state = DistanciaEnVivo(metros: _calculadora.distanciaMetros);
    });
    ref.listen(cronometroProvider.select((estado) => estado.marcha), (
      anterior,
      actual,
    ) {
      if (anterior == MarchaCronometro.pausado &&
          actual == MarchaCronometro.enCurso) {
        _calculadora.reiniciarAncla();
      }
    });

    // Puntos registrados antes de que alguien observara la distancia.
    _procesar(ref.read(recorridoProvider).puntos);
    return DistanciaEnVivo(metros: _calculadora.distanciaMetros);
  }

  /// Pasa por la calculadora solo los puntos que aún no se evaluaron.
  void _procesar(List<PuntoGps> puntos) {
    if (puntos.length < _procesados) {
      // El recorrido se reinició (nueva actividad).
      _calculadora.reiniciar();
      _procesados = 0;
    }
    for (var i = _procesados; i < puntos.length; i++) {
      _calculadora.agregar(puntos[i]);
    }
    _procesados = puntos.length;
  }
}
