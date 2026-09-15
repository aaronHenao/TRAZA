import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_cronometro.dart';
import 'cronometro_service.dart';
import 'reloj_provider.dart';

export 'reloj_provider.dart';

/// Cada cuánto se refresca el cronómetro en pantalla (SCRUM-105).
///
/// Se refresca varias veces por segundo para que el salto de segundo
/// se vea sin retraso perceptible, aunque el formato sea `HH:MM:SS`.
final intervaloRefrescoProvider =
    Provider<Duration>((ref) => const Duration(milliseconds: 200));

/// Estado del cronómetro del entrenamiento en curso.
final cronometroProvider =
    NotifierProvider<CronometroNotifier, EstadoCronometro>(
  CronometroNotifier.new,
);

class CronometroNotifier extends Notifier<EstadoCronometro> {
  late final CronometroService _service;
  Timer? _ticker;

  @override
  EstadoCronometro build() {
    _service = CronometroService(reloj: ref.watch(relojProvider));
    ref.onDispose(_detenerTicker);
    return const EstadoCronometro.inicial();
  }

  /// Arranca el cronómetro desde cero al iniciar la actividad.
  void iniciar() {
    _service.iniciar();
    _arrancarTicker();
    _sincronizar();
  }

  void pausar() {
    _service.pausar();
    _detenerTicker();
    _sincronizar();
  }

  void reanudar() {
    _service.reanudar();
    _arrancarTicker();
    _sincronizar();
  }

  void alternarPausa() {
    if (state.estaEnCurso) {
      pausar();
    } else if (state.estaPausado) {
      reanudar();
    }
  }

  /// Finaliza la actividad; el tiempo total queda disponible en el estado.
  void detener() {
    _service.detener();
    _detenerTicker();
    _sincronizar();
  }

  void reiniciar() {
    _service.reiniciar();
    _detenerTicker();
    _sincronizar();
  }

  /// Refresca el estado contra el reloj real.
  ///
  /// La pantalla la llama al volver de segundo plano para que el tiempo
  /// se ponga al día de inmediato, sin esperar al siguiente tick.
  void sincronizar() => _sincronizar();

  void _arrancarTicker() {
    _detenerTicker();
    _ticker = Timer.periodic(
      ref.read(intervaloRefrescoProvider),
      (_) => _sincronizar(),
    );
  }

  void _detenerTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _sincronizar() => state = _service.estado;
}
