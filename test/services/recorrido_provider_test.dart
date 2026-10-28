import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recorrido.dart';
import 'package:traza/services/almacen_recorrido.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/almacen_recorrido_falso.dart';
import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

void main() {
  late FuenteUbicacionFalsa fuente;
  late RepositorioPuntosGpsFalso repositorio;
  late AlmacenRecorridoFalso almacen;
  late ProviderContainer container;

  const entrenamientoId = 'e-123';

  ProviderContainer crearContainer({String? entrenamiento = entrenamientoId}) {
    final c = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(RelojFalso().call),
        fuenteUbicacionProvider.overrideWithValue(fuente),
        almacenRecorridoProvider.overrideWithValue(almacen),
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
    almacen = AlmacenRecorridoFalso();
    addTearDown(() => fuente.cerrar());
  });

  /// Emite [cuantos] puntos separados lo bastante para que todos cuenten
  /// como avance.
  Future<void> correr(int cuantos, {double desde = 6.2311}) async {
    for (var i = 0; i < cuantos; i++) {
      await emitir(desde + i * 0.0005, -75.6105);
    }
  }

  group('registro en local', () {
    test('empieza vacío y pendiente de sincronizar', () async {
      await montar();

      expect(recorrido().puntos, isEmpty);
      expect(recorrido().sincronizacion, EstadoSincronizacion.pendiente);
    });

    test('acumula cada lectura en orden de captura sin tocar la red', () async {
      await montar();

      await emitir(6.2311, -75.6105);
      await emitir(6.2312, -75.6106);
      await emitir(6.2313, -75.6107);

      expect(recorrido().puntos.map((p) => p.latitud), [
        6.2311,
        6.2312,
        6.2313,
      ]);
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

    test('al reanudar tras moverse en pausa abre un tramo nuevo', () async {
      await montar();
      await emitir(6.2311, -75.6105);
      await emitir(6.2312, -75.6106);

      container.read(cronometroProvider.notifier).pausar();
      await emitir(6.2400, -75.6200);
      container.read(cronometroProvider.notifier).reanudar();
      // Primera lectura tras reanudar, lejos de donde se pausó: empieza el
      // tramo nuevo, no se une con el anterior (BUG-005).
      await emitir(6.2400, -75.6200);
      await emitir(6.2401, -75.6201);

      expect(recorrido().tramos.map((tramo) => tramo.map((p) => p.latitud)), [
        [6.2311, 6.2312],
        [6.2400, 6.2401],
      ]);
      // Para guardar sigue siendo una sola lista en orden de captura.
      expect(recorrido().puntos.length, 4);

      // Y el lote lleva dónde empieza cada tramo, para el resumen.
      await sincronizar();
      expect(repositorio.lotes.single.cortes, [2]);
    });

    test(
      'pausar y reanudar sin lecturas en medio no deja tramos vacíos',
      () async {
        await montar();
        await emitir(6.2311, -75.6105);
        container.read(cronometroProvider.notifier).pausar();
        container.read(cronometroProvider.notifier).reanudar();
        container.read(cronometroProvider.notifier).pausar();
        container.read(cronometroProvider.notifier).reanudar();
        await emitir(6.2312, -75.6106);

        expect(recorrido().tramos.length, 2);
      },
    );

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
      addTearDown(() => container.read(cronometroProvider.notifier).detener());

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
      expect(repositorio.lotes.single.puntos.map((p) => p.latitud), [
        6.2311,
        6.2312,
        6.2313,
      ]);
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

    test(
      'si el envío falla conserva los puntos y permite reintentar',
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
      },
    );
  });

  group('offline first (SCRUM-292)', () {
    test(
      'cada punto se guarda en disco según se captura, no al final',
      () async {
        await montar();

        await correr(3);

        // Sin haber finalizado nada, los tres están a salvo.
        expect(almacen.guardados[entrenamientoId], hasLength(3));
        expect(repositorio.lotes, isEmpty, reason: 'todavía no toca lote');
      },
    );

    test('lo guardado lleva su orden y su tramo', () async {
      await montar();

      await correr(2);
      container.read(cronometroProvider.notifier).alternarPausa();
      container.read(cronometroProvider.notifier).alternarPausa();
      await correr(2, desde: 6.2400);

      final guardados = almacen.guardados[entrenamientoId]!;
      expect(guardados.map((p) => p.orden), [0, 1, 2, 3]);
      // La primera lectura tras reanudar abre tramo (BUG-005).
      expect(guardados.map((p) => p.tramo), [0, 0, 1, 1]);
    });

    test('envía un lote al llegar a la cuenta, sin esperar al final', () async {
      await montar();

      await correr(RecorridoNotifier.puntosPorLote);

      expect(repositorio.lotes, hasLength(1));
      expect(
        repositorio.puntosDe(entrenamientoId),
        hasLength(RecorridoNotifier.puntosPorLote),
      );
    });

    test('lo ya enviado no se vuelve a mandar en el lote siguiente', () async {
      await montar();

      await correr(RecorridoNotifier.puntosPorLote * 2);

      expect(repositorio.lotes, hasLength(2));
      expect(repositorio.lotes[0].ordenes.first, 0);
      // El segundo lote empieza donde acabó el primero.
      expect(
        repositorio.lotes[1].ordenes.first,
        RecorridoNotifier.puntosPorLote,
      );
    });

    test('sin red los puntos siguen en disco y no se pierde ninguno', () async {
      await montar();
      repositorio.fallar = true;

      await correr(RecorridoNotifier.puntosPorLote + 5);

      expect(recorrido().sincronizacion, EstadoSincronizacion.fallida);
      expect(repositorio.puntosDe(entrenamientoId), isEmpty);
      // Lo que importa: no se perdió nada.
      expect(
        await almacen.pendientes(entrenamientoId),
        hasLength(RecorridoNotifier.puntosPorLote + 5),
      );
    });

    test(
      'tras un fallo no se reintenta en cada punto, sino al lote siguiente',
      () async {
        await montar();
        repositorio.fallar = true;

        // Tres lotes de puntos con la red caída.
        await correr(RecorridoNotifier.puntosPorLote * 3);

        // Sin esto, el primer fallo dejaba el contador pasado y cada punto
        // nuevo lanzaba otra petición: se veía en el emulador como una cada
        // dos segundos, y aquí serían 41 intentos en vez de 3.
        expect(repositorio.intentos, 3);
      },
    );

    test(
      'cuando vuelve la red, el siguiente lote sube todo lo atrasado',
      () async {
        await montar();
        repositorio.fallar = true;
        await correr(RecorridoNotifier.puntosPorLote);
        expect(repositorio.puntosDe(entrenamientoId), isEmpty);

        repositorio.fallar = false;
        await correr(RecorridoNotifier.puntosPorLote);

        expect(
          repositorio.puntosDe(entrenamientoId),
          hasLength(RecorridoNotifier.puntosPorLote * 2),
        );
        expect(await almacen.pendientes(entrenamientoId), isEmpty);
      },
    );

    test('al finalizar manda lo que quede pendiente', () async {
      await montar();

      await correr(5);
      expect(repositorio.lotes, isEmpty);

      expect(await sincronizar(), isTrue);

      expect(repositorio.puntosDe(entrenamientoId), hasLength(5));
      expect(await almacen.pendientes(entrenamientoId), isEmpty);
    });

    test('reenviar un lote que ya entró no duplica nada', () async {
      await montar();
      await correr(5);
      await sincronizar();

      // Como si la respuesta se hubiera perdido y se reintentara: la base
      // descarta lo que ya tiene (índice único de 0053).
      await repositorio.guardarLote(
        entrenamientoId: entrenamientoId,
        puntos: almacen.guardados[entrenamientoId]!,
      );

      expect(repositorio.puntosDe(entrenamientoId), hasLength(5));
      expect(repositorio.puntosDe(entrenamientoId).map((p) => p.orden), [
        0,
        1,
        2,
        3,
        4,
      ]);
    });

    test('sin entrenamiento creado no se guarda nada en disco', () async {
      await montar(entrenamiento: null);

      await correr(3);

      expect(recorrido().puntos, hasLength(3), reason: 'el trazo sí se ve');
      expect(almacen.guardados, isEmpty);
    });
  });
}
