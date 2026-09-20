import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recorrido.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

void main() {
  late FuenteUbicacionFalsa fuente;
  late RepositorioPuntosGpsFalso repositorio;
  late ProviderContainer container;

  const entrenamientoId = 'e-123';

  ProviderContainer crearContainer({String? entrenamiento = entrenamientoId}) {
    final c = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(RelojFalso().call),
        fuenteUbicacionProvider.overrideWithValue(fuente),
        repositorioPuntosGpsProvider.overrideWithValue(repositorio),
        entrenamientoActualProvider.overrideWithValue(entrenamiento),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Monta el container como lo vería la pantalla de entrenamiento:
  /// cronómetro en marcha y recorrido observado.
  Future<void> montar({String? entrenamiento = entrenamientoId}) async {
    container = crearContainer(entrenamiento: entrenamiento);
    container.listen(recorridoProvider, (_, _) {});
    container.read(cronometroProvider.notifier).iniciar();
    addTearDown(() => container.read(cronometroProvider.notifier).detener());
    await pumpEventQueue();
  }

  Future<void> emitir(double latitud, double longitud) async {
    fuente.emitir(puntoDePrueba(latitud: latitud, longitud: longitud));
    await pumpEventQueue();
  }

  Recorrido recorrido() => container.read(recorridoProvider);

  Future<bool> sincronizar() =>
      container.read(recorridoProvider.notifier).sincronizar();

  setUp(() {
    fuente = FuenteUbicacionFalsa();
    repositorio = RepositorioPuntosGpsFalso();
    addTearDown(() => fuente.cerrar());
  });

  group('registro en local', () {
    test('empieza vacío y pendiente de sincronizar', () async {
      await montar();

      expect(recorrido().puntos, isEmpty);
      expect(recorrido().sincronizacion, EstadoSincronizacion.pendiente);
    });

    test('acumula cada lectura en orden de captura sin tocar la red',
        () async {
      await montar();

      await emitir(6.2311, -75.6105);
      await emitir(6.2312, -75.6106);
      await emitir(6.2313, -75.6107);

      expect(
        recorrido().puntos.map((p) => p.latitud),
        [6.2311, 6.2312, 6.2313],
      );
      expect(recorrido().ultimo!.longitud, -75.6107);
      expect(repositorio.lotes, isEmpty);
    });

    test('en pausa no registra lecturas y al reanudar sigue', () async {
      await montar();
      await emitir(6.2311, -75.6105);

      container.read(cronometroProvider.notifier).pausar();
      await emitir(6.2350, -75.6140);
      await emitir(6.2360, -75.6150);

      expect(recorrido().puntos.length, 1);

      container.read(cronometroProvider.notifier).reanudar();
      await emitir(6.2312, -75.6106);

      expect(recorrido().puntos.length, 2);
    });

    test('ignora una lectura idéntica a la anterior', () async {
      await montar();

      await emitir(6.2311, -75.6105);
      await emitir(6.2311, -75.6105);
      await emitir(6.2312, -75.6106);
      await emitir(6.2311, -75.6105);

      expect(recorrido().puntos.length, 3);
    });

    test('tras finalizar la actividad ya no registra', () async {
      await montar();
      await emitir(6.2311, -75.6105);

      container.read(cronometroProvider.notifier).detener();
      await emitir(6.2312, -75.6106);

      expect(recorrido().puntos.length, 1);
    });

    test('al dejar de observarlo el recorrido se descarta', () async {
      container = crearContainer();
      container.read(cronometroProvider.notifier).iniciar();
      addTearDown(
        () => container.read(cronometroProvider.notifier).detener(),
      );

      final sub = container.listen(recorridoProvider, (_, _) {});
      await pumpEventQueue();
      await emitir(6.2311, -75.6105);
      expect(recorrido().puntos.length, 1);

      sub.close();
      await pumpEventQueue();
      container.listen(recorridoProvider, (_, _) {});

      expect(recorrido().puntos, isEmpty);
    });
  });

  group('sincronizar al finalizar', () {
    test('envía todos los puntos en un solo lote, en orden', () async {
      await montar();
      await emitir(6.2311, -75.6105);
      await emitir(6.2312, -75.6106);
      await emitir(6.2313, -75.6107);

      final ok = await sincronizar();

      expect(ok, isTrue);
      expect(repositorio.lotes.length, 1);
      expect(repositorio.lotes.single.entrenamientoId, entrenamientoId);
      expect(
        repositorio.lotes.single.puntos.map((p) => p.latitud),
        [6.2311, 6.2312, 6.2313],
      );
      expect(recorrido().sincronizacion, EstadoSincronizacion.completada);
    });

    test('sin puntos no llama al repositorio', () async {
      await montar();

      final ok = await sincronizar();

      expect(ok, isTrue);
      expect(repositorio.lotes, isEmpty);
      expect(recorrido().sincronizacion, EstadoSincronizacion.completada);
    });

    test('sin entrenamiento en curso se queda en local', () async {
      await montar(entrenamiento: null);
      await emitir(6.2311, -75.6105);

      final ok = await sincronizar();

      expect(ok, isTrue);
      expect(repositorio.lotes, isEmpty);
      expect(recorrido().puntos.length, 1);
    });

    test('si el envío falla conserva los puntos y permite reintentar',
        () async {
      await montar();
      await emitir(6.2311, -75.6105);
      await emitir(6.2312, -75.6106);
      repositorio.fallar = true;

      final primero = await sincronizar();

      expect(primero, isFalse);
      expect(recorrido().sincronizacion, EstadoSincronizacion.fallida);
      expect(recorrido().puntos.length, 2);

      repositorio.fallar = false;
      final segundo = await sincronizar();

      expect(segundo, isTrue);
      expect(repositorio.lotes.single.puntos.length, 2);
      expect(recorrido().sincronizacion, EstadoSincronizacion.completada);
    });
  });
}
