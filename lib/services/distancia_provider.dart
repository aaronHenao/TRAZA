import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/distancia_en_vivo.dart';
import '../models/estado_cronometro.dart';
import 'calculadora_distancia.dart';
import 'cronometro_provider.dart';
import 'ubicacion_provider.dart';
import 'ventana_velocidad.dart';

/// Cómo se construye la calculadora de cada actividad. Las pruebas la
/// sobrescriben para ajustar los umbrales del filtro.
final fabricaCalculadoraDistanciaProvider =
    Provider<CalculadoraDistancia Function()>(
      (ref) => CalculadoraDistancia.new,
    );

/// Cómo se construye la ventana del ritmo actual. Las pruebas la
/// sobrescriben para ajustarla.
final fabricaVentanaVelocidadProvider = Provider<VentanaVelocidad Function()>(
  (ref) => VentanaVelocidad.new,
);

/// Distancia recorrida y ritmo actual de la actividad en curso (SCRUM-111,
/// SCRUM-112 y SCRUM-116).
///
/// Evalúa **cada** lectura de [posicionEnVivoProvider] con la actividad en
/// curso, no solo los puntos que se guardan como recorrido: la velocidad
/// Doppler se integra lectura a lectura, y saltarse las de reposo haría que
/// una parada se contara como si se hubiera seguido caminando. No abre un
/// GPS propio: comparte el stream con el mapa y el recorrido.
///
/// En pausa no se evalúa nada, y al reanudar se rompe la continuidad para
/// no contar lo que el usuario se movió con la actividad pausada.
///
/// Vive mientras la pantalla de entrenamiento lo observe.
final distanciaProvider =
    NotifierProvider.autoDispose<DistanciaNotifier, DistanciaEnVivo>(
      DistanciaNotifier.new,
    );

class DistanciaNotifier extends AutoDisposeNotifier<DistanciaEnVivo> {
  late CalculadoraDistancia _calculadora;
  late VentanaVelocidad _ventana;
  late Reloj _reloj;

  @override
  DistanciaEnVivo build() {
    _calculadora = ref.watch(fabricaCalculadoraDistanciaProvider)();
    _ventana = ref.watch(fabricaVentanaVelocidadProvider)();
    _reloj = ref.watch(relojProvider);

    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      final punto = siguiente.valueOrNull;
      if (punto == null) return;
      if (!ref.read(cronometroProvider).estaEnCurso) return;

      _calculadora.agregar(punto);
      final velocidad = _calculadora.ultimaVelocidadMps;
      if (velocidad != null) _ventana.agregar(velocidad, _reloj());
      _publicar();
    });

    ref.listen(cronometroProvider.select((estado) => estado.marcha), (
      anterior,
      actual,
    ) {
      if (actual != MarchaCronometro.enCurso) return;
      if (anterior == MarchaCronometro.detenido) {
        // Actividad nueva: se empieza de cero.
        _calculadora.reiniciar();
        _ventana.reiniciar();
      } else if (anterior == MarchaCronometro.pausado) {
        _calculadora.reiniciarAncla();
        _ventana.reiniciar();
      }
      _publicar();
    });

    // Sin lecturas nuevas (señal perdida) las muestras caducan y el ritmo
    // desaparece con el tiempo, en vez de quedarse congelado.
    ref.listen(cronometroProvider.select((estado) => estado.transcurrido), (
      _,
      _,
    ) {
      _publicar();
    });

    return _instantanea();
  }

  void _publicar() => state = _instantanea();

  DistanciaEnVivo _instantanea() => DistanciaEnVivo(
    metros: _calculadora.distanciaMetros,
    ritmoActual: _ventana.ritmoPorKm(_reloj()),
  );
}
