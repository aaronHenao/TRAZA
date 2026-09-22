import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/estado_cronometro.dart';
import 'package:traza/services/auto_pausa_provider.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

/// Auto-pausa por reposo (SCRUM-116).
///
/// El usuario que se para en un semáforo no está entrenando: si el tiempo
/// sigue corriendo, el ritmo promedio se dispara y el resumen miente. Y al
/// arrancar de nuevo tiene que notarse enseguida, no varios segundos
/// después.
void main() {
  late FuenteUbicacionFalsa fuente;
  late RelojFalso reloj;
  late ProviderContainer container;

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    reloj = RelojFalso();
    addTearDown(() => fuente.cerrar());
  });

  /// Monta el container como lo vería la pantalla de entrenamiento.
  Future<void> montar() async {
    container = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(reloj.call),
        fuenteUbicacionProvider.overrideWithValue(fuente),
        repositorioPuntosGpsProvider.overrideWithValue(
          RepositorioPuntosGpsFalso(),
        ),
        entrenamientoActualProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    container.listen(recorridoProvider, (_, _) {});
    container.listen(autoPausaProvider, (_, _) {});
    container.read(cronometroProvider.notifier).iniciar();
    addTearDown(() => container.read(cronometroProvider.notifier).detener());
    await pumpEventQueue();
  }

  /// Emite una lectura y deja que llegue a los providers. El reloj y la
  /// marca de la lectura van juntos: lo que pasa en el teléfono.
  Future<void> emitir(double latitud, {required int segundos}) async {
    fuente.emitir(
      puntoDePrueba(
        latitud: latitud,
        capturadoEn: DateTime(2026, 1, 1, 8).add(Duration(seconds: segundos)),
      ),
    );
    await pumpEventQueue();
  }

  /// Avanza el reloj y refresca el cronómetro, como haría su tick.
  Future<void> tic(Duration cuanto) async {
    reloj.avanzar(cuanto);
    container.read(cronometroProvider.notifier).sincronizar();
    await pumpEventQueue();
  }

  MarchaCronometro marcha() => container.read(cronometroProvider).marcha;

  test('quieto con el GPS informando, congela el tiempo', () async {
    await montar();
    await emitir(6.2311, segundos: 0);

    // Lecturas que llegan pero no se mueven de sitio (jitter de ~1 m).
    await tic(const Duration(seconds: 5));
    await emitir(6.23111, segundos: 5);
    expect(marcha(), MarchaCronometro.enCurso);

    await tic(const Duration(seconds: 6));
    await emitir(6.23110, segundos: 11);
    expect(marcha(), MarchaCronometro.enCurso);

    // Pasados los 15 s de reposo ya no cuenta como entrenamiento.
    await tic(const Duration(seconds: 5));
    await emitir(6.23111, segundos: 16);

    expect(marcha(), MarchaCronometro.autoPausado);
    expect(container.read(autoPausaProvider), isTrue);
  });

  test('el tiempo congelado no crece mientras dura el reposo', () async {
    await montar();
    await emitir(6.2311, segundos: 0);
    await tic(const Duration(seconds: 16));
    await emitir(6.23111, segundos: 16);
    expect(marcha(), MarchaCronometro.autoPausado);

    final congelado = container.read(cronometroProvider).transcurrido;
    await tic(const Duration(minutes: 2));

    expect(container.read(cronometroProvider).transcurrido, congelado);
  });

  test('al volver a moverse el tiempo arranca solo', () async {
    await montar();
    await emitir(6.2311, segundos: 0);
    await tic(const Duration(seconds: 16));
    await emitir(6.23111, segundos: 16);
    expect(marcha(), MarchaCronometro.autoPausado);

    // Arranca de nuevo: 111 m más allá.
    await tic(const Duration(seconds: 30));
    await emitir(6.2321, segundos: 46);

    expect(marcha(), MarchaCronometro.enCurso);
    expect(container.read(autoPausaProvider), isFalse);
  });

  test('lo recorrido durante la auto-pausa sí cuenta', () async {
    await montar();
    await emitir(6.2311, segundos: 0);
    await tic(const Duration(seconds: 16));
    await emitir(6.23111, segundos: 16);

    await tic(const Duration(seconds: 30));
    await emitir(6.2321, segundos: 46);

    // A diferencia de la pausa manual, aquí no se rompe la continuidad:
    // el usuario nunca dejó de entrenar, solo se quedó quieto.
    expect(container.read(recorridoProvider).puntos, hasLength(2));
  });

  test('sin lecturas recientes no congela: puede ser señal perdida', () async {
    await montar();
    await emitir(6.2311, segundos: 0);

    // Pasan 40 s sin que el GPS entregue nada. No se puede saber si el
    // usuario está quieto o si se metió en un túnel corriendo: el tiempo
    // sigue.
    await tic(const Duration(seconds: 40));

    expect(marcha(), MarchaCronometro.enCurso);
  });

  test('la pausa manual no la levanta el detector', () async {
    await montar();
    await emitir(6.2311, segundos: 0);
    container.read(cronometroProvider.notifier).pausar();

    await tic(const Duration(seconds: 30));
    await emitir(6.2321, segundos: 30);

    expect(marcha(), MarchaCronometro.pausado);
  });

  test('en pausa manual tampoco auto-pausa', () async {
    await montar();
    container.read(cronometroProvider.notifier).pausar();

    await emitir(6.2311, segundos: 0);
    await tic(const Duration(seconds: 40));

    expect(marcha(), MarchaCronometro.pausado);
  });
}
