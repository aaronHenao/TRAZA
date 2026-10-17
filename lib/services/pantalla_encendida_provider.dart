import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'cronometro_provider.dart';

/// Evita que el sistema apague la pantalla por inactividad.
///
/// La app usa [PantallaEncendidaWakelock]; las pruebas inyectan una falsa
/// que solo anota lo que se le pide.
abstract class PantallaEncendida {
  /// `true`: la pantalla no se apaga sola. `false`: vuelve a apagarse con
  /// el tiempo de espera del sistema.
  Future<void> mantener({required bool encendida});
}

/// Implementación con `wakelock_plus`. Solo afecta a la ventana de la app:
/// si el usuario la deja en segundo plano o bloquea el teléfono, el sistema
/// hace lo de siempre.
class PantallaEncendidaWakelock implements PantallaEncendida {
  const PantallaEncendidaWakelock();

  @override
  Future<void> mantener({required bool encendida}) =>
      WakelockPlus.toggle(enable: encendida);
}

final pantallaEncendidaProvider = Provider<PantallaEncendida>(
  (ref) => const PantallaEncendidaWakelock(),
);

/// Mantiene la pantalla encendida mientras la actividad está en curso, para
/// ver el mapa, el tiempo y el ritmo sin tocar el teléfono.
///
/// Solo en ruta: antes de iniciar, en pausa y al finalizar la pantalla se
/// apaga como siempre, y al salir de la pantalla de entrenamiento se libera
/// aunque la actividad siga (autoDispose). La pantalla de entrenamiento lo
/// observa mientras está abierta.
final pantallaEncendidaEnRutaProvider = Provider.autoDispose<void>((ref) {
  final pantalla = ref.watch(pantallaEncendidaProvider);

  void mantener(bool encendida) {
    pantalla.mantener(encendida: encendida).catchError((Object error) {
      // Sin esto solo se pierde la comodidad: el entrenamiento sigue igual.
      debugPrint('No se pudo cambiar el apagado de la pantalla: $error');
    });
  }

  ref.listen(
    cronometroProvider.select((estado) => estado.estaEnCurso),
    (_, enCurso) => mantener(enCurso),
    fireImmediately: true,
  );
  ref.onDispose(() => mantener(false));
});
