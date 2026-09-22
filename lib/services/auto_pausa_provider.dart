import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_cronometro.dart';
import 'cronometro_provider.dart';
import 'distancia_provider.dart';
import 'ubicacion_provider.dart';

/// Cuánto tiene que estar quieto el usuario antes de congelar el tiempo.
///
/// Con el filtro de registro en 5 m, alguien caminando muy despacio
/// (0,5 m/s) produce un tramo cada ~10 s: por debajo de ese margen se
/// auto-pausaría a gente que sí se está moviendo.
final umbralReposoProvider =
    Provider<Duration>((ref) => const Duration(seconds: 15));

/// Hasta cuándo se considera que el GPS sigue informando.
///
/// Sin lecturas recientes no se puede saber si el usuario está quieto o si
/// simplemente se perdió la señal (un túnel, el bolsillo). En ese caso el
/// tiempo sigue corriendo: es preferible contar de más que congelarle el
/// cronómetro a alguien que está corriendo.
final umbralSinSenalProvider =
    Provider<Duration>((ref) => const Duration(seconds: 10));

/// Congela el cronómetro cuando el usuario se queda quieto y lo reanuda en
/// cuanto vuelve a moverse (SCRUM-116).
///
/// `true` mientras la auto-pausa esté actuando. No dibuja nada: cambia la
/// marcha del [cronometroProvider], que es lo que mira la pantalla.
///
/// Se apoya en el tick del cronómetro en vez de montar su propio temporizador:
/// ya se refresca varias veces por segundo y así no hay dos relojes que
/// puedan desincronizarse.
final autoPausaProvider =
    NotifierProvider.autoDispose<AutoPausaNotifier, bool>(
  AutoPausaNotifier.new,
);

class AutoPausaNotifier extends AutoDisposeNotifier<bool> {
  late Reloj _reloj;

  /// Desde cuándo no se detecta movimiento. Se reinicia con cada tramo
  /// nuevo y cada vez que el cronómetro arranca o se reanuda.
  DateTime? _quietoDesde;

  /// Último tramo visto, para saber si llegó movimiento nuevo.
  DateTime? _ultimoMovimiento;

  /// Cuándo llegó la última lectura del GPS, sea o no movimiento.
  DateTime? _ultimaLectura;

  @override
  bool build() {
    _reloj = ref.watch(relojProvider);

    // Mantiene viva la distancia: de ahí salen los tramos aceptados.
    ref.listen(distanciaProvider, (_, _) => _revisar());

    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      if (siguiente.valueOrNull == null) return;
      _ultimaLectura = _reloj();
      // Cada lectura es una oportunidad de decidir: no hay que esperar al
      // siguiente tick del cronómetro, que además está parado durante la
      // auto-pausa.
      _revisar();
    });

    ref.listen(cronometroProvider.select((estado) => estado.marcha), (_, _) {
      // Se lee la marcha en vez de usar la que trae el aviso: cuando el
      // cambio sale de este mismo notifier, Riverpod puede entregar el
      // aviso más tarde y con el valor de antes.
      final marcha = ref.read(cronometroProvider).marcha;
      // Arrancar, reanudar o pausar a mano borra el reposo acumulado: la
      // cuenta empieza de nuevo desde este instante.
      if (marcha != MarchaCronometro.autoPausado) {
        _quietoDesde = _reloj();
      }
      _publicar(marcha);
    });

    ref.listen(cronometroProvider.select((estado) => estado.transcurrido), (
      _,
      _,
    ) {
      _revisar();
    });

    return ref.read(cronometroProvider).estaAutoPausado;
  }

  void _revisar() {
    final ahora = _reloj();
    final movimiento = ref.read(distanciaProvider.notifier).ultimoMovimiento;
    final hayMovimientoNuevo =
        movimiento != null && movimiento != _ultimoMovimiento;
    if (hayMovimientoNuevo) {
      _ultimoMovimiento = movimiento;
      _quietoDesde = ahora;
    }

    final marcha = ref.read(cronometroProvider).marcha;
    final cronometro = ref.read(cronometroProvider.notifier);

    switch (marcha) {
      case MarchaCronometro.enCurso:
        if (_quietoDesde == null) {
          _quietoDesde = ahora;
          return;
        }
        if (!_gpsInforma(ahora)) return;
        if (ahora.difference(_quietoDesde!) < ref.read(umbralReposoProvider)) {
          return;
        }
        cronometro.autoPausar();
        _publicar(ref.read(cronometroProvider).marcha);
      case MarchaCronometro.autoPausado:
        if (!hayMovimientoNuevo) return;
        cronometro.autoReanudar();
        _publicar(ref.read(cronometroProvider).marcha);
      case MarchaCronometro.pausado:
      case MarchaCronometro.detenido:
        return;
    }
  }

  /// Publica la marcha como bandera.
  void _publicar(MarchaCronometro marcha) {
    final autoPausado = marcha == MarchaCronometro.autoPausado;
    if (state != autoPausado) state = autoPausado;
  }

  /// `true` si el GPS entregó algo hace poco. Sin lecturas no se puede
  /// distinguir "quieto" de "sin señal".
  bool _gpsInforma(DateTime ahora) {
    final lectura = _ultimaLectura;
    if (lectura == null) return false;
    return ahora.difference(lectura) <= ref.read(umbralSinSenalProvider);
  }
}
