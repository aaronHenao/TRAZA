import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/pantalla_encendida_provider.dart';

import '../utiles/pantalla_encendida_falsa.dart';
import '../utiles/reloj_falso.dart';

/// La pantalla no se apaga solo con la actividad en curso.
void main() {
  late PantallaEncendidaFalsa pantalla;
  late ProviderContainer container;
  late ProviderSubscription<void> suscripcion;

  CronometroNotifier cronometro() =>
      container.read(cronometroProvider.notifier);

  setUp(() {
    pantalla = PantallaEncendidaFalsa();
    container = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(RelojFalso().call),
        pantallaEncendidaProvider.overrideWithValue(pantalla),
      ],
    );
    addTearDown(container.dispose);
    // Como la pantalla de entrenamiento: lo observa mientras esté abierta.
    suscripcion = container.listen(pantallaEncendidaEnRutaProvider, (_, _) {});
    addTearDown(() => cronometro().detener());
  });

  test('antes de iniciar la actividad la pantalla puede apagarse', () {
    expect(pantalla.encendida, isFalse);
  });

  test('con la actividad en curso la pantalla no se apaga', () {
    cronometro().iniciar();

    expect(pantalla.encendida, isTrue);
  });

  test('en pausa vuelve a poder apagarse y al reanudar no', () {
    cronometro().iniciar();
    cronometro().pausar();
    expect(pantalla.encendida, isFalse);

    cronometro().reanudar();
    expect(pantalla.encendida, isTrue);
  });

  test('al finalizar la actividad puede apagarse', () {
    cronometro().iniciar();
    cronometro().detener();

    expect(pantalla.encendida, isFalse);
  });

  test('al salir de la pantalla de entrenamiento puede apagarse aunque la '
      'actividad siga en curso', () async {
    cronometro().iniciar();
    suscripcion.close();
    // autoDispose libera el provider al final del frame.
    await container.pump();

    expect(pantalla.encendida, isFalse);
  });

  test('no repite la petición si el estado no cambia', () {
    cronometro().iniciar();
    cronometro().pausar();
    cronometro().detener();

    // Detener desde pausa no cambia "en curso": sigue en false.
    expect(pantalla.peticiones, [false, true, false]);
  });
}
