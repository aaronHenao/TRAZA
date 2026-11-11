import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_pendiente.dart';
import 'package:traza/models/recorrido_local.dart';
import 'package:traza/services/almacen_recorrido.dart';
import 'package:traza/services/almacen_recorrido_drift.dart';
import 'package:traza/services/base_local.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/recorrido_provider.dart'
    show repositorioPuntosGpsProvider;
import 'package:traza/services/reenvio_recorridos.dart';
import 'package:traza/services/rutas_oficiales_service.dart';

import '../utiles/almacen_recorrido_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';
import '../utiles/rutas_oficiales_repository_falso.dart';

/// Los puntos del recorrido guardados en SQLite con Drift (Drift, Desarrollo
/// Móvil).
///
/// Usa una base SQLite de verdad, en memoria: lo que se prueba aquí son
/// justamente las tablas y las consultas, así que un doble no serviría de
/// nada. Cada prueba empieza con una base vacía.
///
/// La cuenta con sesión es una variable que la prueba cambia a mano, para
/// simular que en el mismo teléfono entra otra persona.
void main() {
  // El provider real lee los archivos viejos con path_provider: sin el
  // binding, ni siquiera llega a fallar como en un teléfono sin permiso.
  TestWidgetsFlutterBinding.ensureInitialized();

  late BaseLocal base;
  String? usuario;
  late DateTime ahora;

  setUp(() {
    base = BaseLocal(NativeDatabase.memory());
    addTearDown(base.close);
    usuario = 'uid-ana';
    ahora = DateTime(2026, 11, 11, 8);
  });

  AlmacenRecorridoDrift abrir({AlmacenRecorrido? archivosViejos}) =>
      AlmacenRecorridoDrift(
        base,
        usuarioActual: () => usuario,
        archivosViejos: archivosViejos,
        reloj: () => ahora,
      );

  /// Guarda [cuantos] puntos seguidos en [entrenamientoId], desde el orden 0.
  Future<void> guardarPuntos(
    AlmacenRecorrido almacen,
    String entrenamientoId,
    int cuantos,
  ) async {
    for (var orden = 0; orden < cuantos; orden++) {
      await almacen.anadir(
        entrenamientoId,
        puntoPendienteDePrueba(orden: orden),
      );
    }
  }

  /// Lo que vería ahora la pantalla de sincronización.
  Future<List<RecorridoLocal>> recorridos(AlmacenRecorrido almacen) =>
      almacen.recorridosDeLaCuenta().first;

  Future<RecorridoLocal> recorridoDe(
    AlmacenRecorrido almacen,
    String entrenamientoId,
  ) async => (await recorridos(
    almacen,
  )).singleWhere((r) => r.entrenamientoId == entrenamientoId);

  /// Cuántas filas tiene [tabla], mirando la base directamente.
  Future<int> filas(String tabla) async {
    final fila = await base
        .customSelect('select count(*) as cuantas from $tabla')
        .getSingle();
    return fila.read<int>('cuantas');
  }

  /// Archivos viejos con un recorrido a medio enviar: el 0 ya entró en la
  /// base, el 1 y el 2 no.
  AlmacenRecorridoFalso archivosConUnRecorrido() => AlmacenRecorridoFalso()
    ..sembrar('ent-viejo', [
      for (var orden = 0; orden < 3; orden++)
        puntoPendienteDePrueba(orden: orden),
    ], enviados: 0);

  group('criterio 1: los puntos se guardan en SQLite con Drift y el tracking '
      'funciona igual que con los archivos', () {
    test('guarda en dos tablas: el recorrido en recorridos_locales y sus '
        'puntos en puntos_locales', () async {
      final almacen = abrir();

      await guardarPuntos(almacen, 'ent-1', 3);

      expect(await filas('recorridos_locales'), 1);
      expect(await filas('puntos_locales'), 3);
    });

    test('la fila de recorridos_locales lleva el id del entrenamiento, el uid '
        'del dueño, la fecha de actualización, pendiente_sync, ultimo_error y '
        'rechazado', () async {
      final almacen = abrir();

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));

      final fila = await base
          .customSelect(
            'select entrenamiento_id, usuario_id, actualizado_en, '
            'pendiente_sync, ultimo_error, rechazado from recorridos_locales',
          )
          .getSingle();
      expect(fila.read<String>('entrenamiento_id'), 'ent-1');
      expect(fila.readNullable<String>('usuario_id'), 'uid-ana');
      expect(fila.read<DateTime>('actualizado_en'), ahora);
      expect(fila.read<bool>('pendiente_sync'), isTrue);
      expect(fila.readNullable<String>('ultimo_error'), isNull);
      expect(fila.read<bool>('rechazado'), isFalse);
    });

    test('anadir deja el recorrido a nombre de la cuenta con sesión, '
        'pendiente de enviar y sin error', () async {
      final almacen = abrir();

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));

      expect(await recorridos(almacen), [
        RecorridoLocal(
          entrenamientoId: 'ent-1',
          usuarioId: 'uid-ana',
          actualizadoEn: ahora,
          pendienteSync: true,
          ultimoError: null,
          rechazado: false,
          puntosSinEnviar: 1,
        ),
      ]);
    });

    test('un punto guardado se puede volver a leer igual', () async {
      final almacen = abrir();
      final punto = puntoPendienteDePrueba(orden: 0, tramo: 1);

      await almacen.anadir('ent-1', punto);

      expect(await almacen.pendientes('ent-1'), [punto]);
    });

    test('conserva la hora de captura con sus milisegundos, como los '
        'archivos', () async {
      final almacen = abrir();
      final punto = puntoPendienteDePrueba(
        orden: 0,
        capturadoEn: DateTime(2026, 10, 27, 10, 0, 1, 250),
      );

      await almacen.anadir('ent-1', punto);

      expect(
        (await almacen.pendientes('ent-1')).single.capturadoEn,
        DateTime(2026, 10, 27, 10, 0, 1, 250),
      );
    });

    test('sin nada guardado no hay pendientes', () async {
      expect(await abrir().pendientes('ent-1'), isEmpty);
    });

    test('pendientes devuelve lo no enviado en orden de captura, aunque se '
        'guarde a destiempo', () async {
      final almacen = abrir();
      for (final orden in [2, 0, 1]) {
        await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: orden));
      }

      final pendientes = await almacen.pendientes('ent-1');

      expect(pendientes.map((p) => p.orden), [0, 1, 2]);
    });

    test('cada entrenamiento guarda lo suyo', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 1);
      await guardarPuntos(almacen, 'ent-2', 2);

      expect(await almacen.pendientes('ent-1'), hasLength(1));
      expect(await almacen.pendientes('ent-2'), hasLength(2));
    });

    test('marcarEnviados da por enviado hasta ese orden incluido, y lo demás '
        'sigue pendiente', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 5);

      await almacen.marcarEnviados('ent-1', 2);

      final pendientes = await almacen.pendientes('ent-1');
      expect(pendientes.map((p) => p.orden), [3, 4]);
    });

    test('marcar enviado el último no deja nada pendiente', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 1);

      await almacen.marcarEnviados('ent-1', 0);

      expect(await almacen.pendientes('ent-1'), isEmpty);
    });

    test('marcar enviado un recorrido que no existe no falla', () async {
      final almacen = abrir();

      await almacen.marcarEnviados('ent-que-no-existe', 3);

      expect(await filas('recorridos_locales'), 0);
    });

    test('olvidar borra todo el recorrido: su fila y todos sus puntos, '
        'enviados o no', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 3);
      await almacen.marcarEnviados('ent-1', 0);
      await guardarPuntos(almacen, 'ent-2', 2);

      await almacen.olvidar('ent-1');

      expect(await almacen.pendientes('ent-1'), isEmpty);
      expect(await almacen.conPendientes(), ['ent-2']);
      expect(await filas('recorridos_locales'), 1);
      expect(await filas('puntos_locales'), 2, reason: 'solo los de ent-2');
    });

    test('olvidar algo que no está no falla', () async {
      await expectLater(abrir().olvidar('ent-que-no-existe'), completes);
    });

    test('repetir un mismo orden no duplica el punto', () async {
      final almacen = abrir();
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 1));

      expect((await almacen.pendientes('ent-1')).map((p) => p.orden), [0, 1]);
      expect(await filas('puntos_locales'), 2);
    });

    test('aguanta un recorrido largo con escrituras a la vez sin perder '
        'ninguna', () async {
      // Un 10 km a un punto cada 5 m son ~2000 puntos, y el provider no
      // espera a que termine una escritura para lanzar la siguiente.
      final almacen = abrir();

      await Future.wait([
        for (var orden = 0; orden < 300; orden++)
          almacen.anadir('ent-1', puntoPendienteDePrueba(orden: orden)),
      ]);

      final pendientes = await almacen.pendientes('ent-1');
      expect(pendientes, hasLength(300));
      expect(pendientes.first.orden, 0);
      expect(pendientes.last.orden, 299);
    });

    test('lo guardado sigue ahí al abrir otro almacén sobre la misma base, '
        'como al reabrir la app', () async {
      await guardarPuntos(abrir(), 'ent-1', 3);

      final reabierto = abrir();

      expect(await reabierto.pendientes('ent-1'), hasLength(3));
      expect(await reabierto.conPendientes(), ['ent-1']);
    });
  });

  group('criterio 2: conPendientes filtra por la cuenta con sesión', () {
    test('solo devuelve los recorridos pendientes de la cuenta con '
        'sesión', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-ana', 2);
      usuario = 'uid-beto';
      await guardarPuntos(almacen, 'ent-beto', 2);

      expect(await almacen.conPendientes(), ['ent-beto']);

      usuario = 'uid-ana';
      expect(await almacen.conPendientes(), ['ent-ana']);
    });

    test('también devuelve los importados sin dueño (usuarioId null), sea '
        'cual sea la cuenta', () async {
      final almacen = abrir(archivosViejos: archivosConUnRecorrido());
      await guardarPuntos(almacen, 'ent-ana', 2);

      expect(
        await almacen.conPendientes(),
        unorderedEquals(['ent-ana', 'ent-viejo']),
      );

      usuario = 'uid-beto';
      expect(await almacen.conPendientes(), ['ent-viejo']);
    });

    test('nunca devuelve los rechazados', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 2);
      await guardarPuntos(almacen, 'ent-2', 2);

      await almacen.registrarError(
        'ent-1',
        RecorridoLocal.motivoRechazado,
        rechazado: true,
      );

      expect(await almacen.conPendientes(), ['ent-2']);
    });

    test('también devuelve los enviados del todo que no se olvidaron, para '
        'que el reenvío los limpie y verifique su ruta', () async {
      // Pasa si la app se cerró entre el último lote y el olvido del cierre:
      // con los archivos, el reenvío los olvidaba. Si no se ofrecieran,
      // quedarían para siempre en la base local.
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 2);

      await almacen.marcarEnviados('ent-1', 1);

      expect(await almacen.conPendientes(), ['ent-1']);
      expect(await almacen.pendientes('ent-1'), isEmpty);
    });

    test('los de otra cuenta no se borran: siguen ahí, enteros, cuando esa '
        'cuenta vuelve', () async {
      final almacen = abrir();
      usuario = 'uid-beto';
      await guardarPuntos(almacen, 'ent-beto', 3);

      usuario = 'uid-ana';
      expect(await almacen.conPendientes(), isEmpty);
      expect(await recorridos(almacen), isEmpty);

      usuario = 'uid-beto';
      expect(await almacen.conPendientes(), ['ent-beto']);
      expect(await almacen.pendientes('ent-beto'), hasLength(3));
    });

    test('al reenviar con la sesión de otra cuenta, los suyos no se suben ni '
        'se borran', () async {
      final almacen = abrir();
      usuario = 'uid-beto';
      await guardarPuntos(almacen, 'ent-beto', 3);
      usuario = 'uid-ana';
      await guardarPuntos(almacen, 'ent-ana', 2);
      final repositorio = RepositorioPuntosGpsFalso();
      final container = ProviderContainer(
        overrides: [
          almacenRecorridoProvider.overrideWithValue(almacen),
          repositorioPuntosGpsProvider.overrideWithValue(repositorio),
          rutasOficialesRepositoryProvider.overrideWithValue(
            RutasOficialesRepositorioFalso(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(reenvioRecorridosProvider.future), 1);

      expect(repositorio.puntosDe('ent-ana'), hasLength(2));
      expect(repositorio.puntosDe('ent-beto'), isEmpty);
      usuario = 'uid-beto';
      expect(await almacen.conPendientes(), ['ent-beto']);
      expect(await almacen.pendientes('ent-beto'), hasLength(3));
    });

    test('sin sesión no devuelve los de ninguna cuenta', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-ana', 2);

      usuario = null;

      expect(await almacen.conPendientes(), isEmpty);
    });
  });

  group('criterio 3: al enviar, pendiente_sync, ultimo_error y actualizado_en '
      'se mantienen al día', () {
    test('si se envió todo, pendiente_sync = false y ultimo_error = '
        'null', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 3);
      await almacen.registrarError('ent-1', RecorridoLocal.motivoSinEnviar);

      await almacen.marcarEnviados('ent-1', 2);

      final recorrido = await recorridoDe(almacen, 'ent-1');
      expect(recorrido.pendienteSync, isFalse);
      expect(recorrido.ultimoError, isNull);
      expect(recorrido.puntosSinEnviar, 0);
    });

    test('si quedan puntos sin enviar, sigue pendiente', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 5);

      await almacen.marcarEnviados('ent-1', 2);

      final recorrido = await recorridoDe(almacen, 'ent-1');
      expect(recorrido.pendienteSync, isTrue);
      expect(recorrido.puntosSinEnviar, 2);
      expect(await almacen.conPendientes(), ['ent-1']);
    });

    test('un envío parcial que sale bien también deja atrás el error '
        'anterior', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 5);
      await almacen.registrarError('ent-1', RecorridoLocal.motivoSinEnviar);

      await almacen.marcarEnviados('ent-1', 2);

      final recorrido = await recorridoDe(almacen, 'ent-1');
      expect(recorrido.pendienteSync, isTrue);
      expect(recorrido.ultimoError, isNull);
    });

    test('un punto nuevo tras enviarlo todo lo vuelve a dejar '
        'pendiente', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 3);
      await almacen.marcarEnviados('ent-1', 2);

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 3));

      final recorrido = await recorridoDe(almacen, 'ent-1');
      expect(recorrido.pendienteSync, isTrue);
      expect(recorrido.puntosSinEnviar, 1);
      expect(await almacen.conPendientes(), ['ent-1']);
    });

    test('cada cambio actualiza actualizado_en', () async {
      final almacen = abrir();

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      expect((await recorridoDe(almacen, 'ent-1')).actualizadoEn, ahora);

      ahora = DateTime(2026, 11, 11, 8, 1);
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 1));
      expect((await recorridoDe(almacen, 'ent-1')).actualizadoEn, ahora);

      ahora = DateTime(2026, 11, 11, 8, 2);
      await almacen.registrarError('ent-1', RecorridoLocal.motivoSinEnviar);
      expect((await recorridoDe(almacen, 'ent-1')).actualizadoEn, ahora);

      ahora = DateTime(2026, 11, 11, 8, 3);
      await almacen.marcarEnviados('ent-1', 1);
      expect((await recorridoDe(almacen, 'ent-1')).actualizadoEn, ahora);
    });
  });

  group('criterio 4: si no se pudo enviar, se anota el motivo sin borrar '
      'nada', () {
    test('registrarError anota el motivo, conserva los puntos y el recorrido '
        'se sigue reintentando', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 3);

      await almacen.registrarError('ent-1', RecorridoLocal.motivoSinEnviar);

      expect(
        await recorridoDe(almacen, 'ent-1'),
        RecorridoLocal(
          entrenamientoId: 'ent-1',
          usuarioId: 'uid-ana',
          actualizadoEn: ahora,
          pendienteSync: true,
          ultimoError: RecorridoLocal.motivoSinEnviar,
          rechazado: false,
          puntosSinEnviar: 3,
        ),
      );
      expect(await almacen.pendientes('ent-1'), hasLength(3));
      expect(await almacen.conPendientes(), ['ent-1']);
    });

    test('registrarError con rechazado: true lo marca rechazado, guarda el '
        'motivo en ultimo_error y no borra ningún punto', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 3);

      await almacen.registrarError(
        'ent-1',
        RecorridoLocal.motivoRechazado,
        rechazado: true,
      );

      final recorrido = await recorridoDe(almacen, 'ent-1');
      expect(recorrido.rechazado, isTrue);
      expect(recorrido.ultimoError, RecorridoLocal.motivoRechazado);
      expect(recorrido.puntosSinEnviar, 3);
      expect(await almacen.pendientes('ent-1'), hasLength(3));
      expect(await filas('puntos_locales'), 3);

      final fila = await base
          .customSelect(
            'select ultimo_error, rechazado from recorridos_locales',
          )
          .getSingle();
      expect(
        fila.readNullable<String>('ultimo_error'),
        RecorridoLocal.motivoRechazado,
      );
      expect(fila.read<bool>('rechazado'), isTrue);
    });

    test('registrarError de un recorrido que no existe no hace nada', () async {
      final almacen = abrir();

      await almacen.registrarError(
        'ent-que-no-existe',
        RecorridoLocal.motivoRechazado,
        rechazado: true,
      );

      expect(await filas('recorridos_locales'), 0);
      expect(await recorridos(almacen), isEmpty);
    });
  });

  group('criterio 5: recorridosDeLaCuenta, para la pantalla de '
      'sincronización', () {
    test('emite los recorridos de la cuenta con sesión, cada uno con sus '
        'puntos sin enviar', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-1', 3);
      await almacen.marcarEnviados('ent-1', 0);

      expect(await recorridos(almacen), [
        RecorridoLocal(
          entrenamientoId: 'ent-1',
          usuarioId: 'uid-ana',
          actualizadoEn: ahora,
          pendienteSync: true,
          ultimoError: null,
          rechazado: false,
          puntosSinEnviar: 2,
        ),
      ]);
    });

    test('no emite los de otra cuenta', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-ana', 1);
      usuario = 'uid-beto';
      await guardarPuntos(almacen, 'ent-beto', 1);

      usuario = 'uid-ana';

      expect((await recorridos(almacen)).map((r) => r.entrenamientoId), [
        'ent-ana',
      ]);
    });

    test('no muestra los importados sin dueño: podrían ser de otra cuenta '
        'del mismo teléfono', () async {
      // Se siguen intentando subir (criterio 2): la base decide de quién
      // son. Lo que no se hace es enseñárselos a una cuenta que tal vez no
      // es la dueña (auditoría de seguridad).
      final almacen = abrir(archivosViejos: archivosConUnRecorrido());

      expect(await recorridos(almacen), isEmpty);
      expect(await almacen.conPendientes(), ['ent-viejo']);
    });

    test('un rechazo sobre un recorrido sin dueño no lo marca rechazado: '
        'su dueño lo podrá subir', () async {
      final almacen = abrir(archivosViejos: archivosConUnRecorrido());
      await almacen.conPendientes();

      await almacen.registrarError(
        'ent-viejo',
        RecorridoLocal.motivoRechazado,
        rechazado: true,
      );

      // Con la sesión de otra cuenta la base dice 42501; eso no significa
      // que nadie lo pueda subir.
      expect(await almacen.conPendientes(), ['ent-viejo']);
    });

    test('van del más reciente al más viejo según su última '
        'actualización', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-a', 1);
      ahora = DateTime(2026, 11, 11, 9);
      await guardarPuntos(almacen, 'ent-b', 1);
      ahora = DateTime(2026, 11, 11, 10);
      await guardarPuntos(almacen, 'ent-c', 1);
      // El más viejo vuelve a cambiar: pasa a ser el más reciente.
      ahora = DateTime(2026, 11, 11, 11);
      await almacen.anadir('ent-a', puntoPendienteDePrueba(orden: 1));

      expect((await recorridos(almacen)).map((r) => r.entrenamientoId), [
        'ent-a',
        'ent-c',
        'ent-b',
      ]);
    });

    test('vuelve a emitir con cada cambio', () async {
      final almacen = abrir();
      final emisiones = <List<RecorridoLocal>>[];
      final suscripcion = almacen.recorridosDeLaCuenta().listen(emisiones.add);
      addTearDown(suscripcion.cancel);

      /// Lo último que vio la pantalla, una vez asentado el cambio.
      Future<List<RecorridoLocal>> ultima() async {
        await pumpEventQueue();
        return emisiones.last;
      }

      expect(await ultima(), isEmpty);

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      expect((await ultima()).single.puntosSinEnviar, 1);

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 1));
      expect((await ultima()).single.puntosSinEnviar, 2);

      await almacen.registrarError('ent-1', RecorridoLocal.motivoSinEnviar);
      expect(
        (await ultima()).single.ultimoError,
        RecorridoLocal.motivoSinEnviar,
      );

      await almacen.marcarEnviados('ent-1', 1);
      expect((await ultima()).single.pendienteSync, isFalse);

      await almacen.olvidar('ent-1');
      expect(await ultima(), isEmpty);
    });

    test('sin sesión no emite los recorridos de ninguna cuenta', () async {
      final almacen = abrir();
      await guardarPuntos(almacen, 'ent-ana', 1);

      usuario = null;

      expect(await recorridos(almacen), isEmpty);
    });
  });

  group('criterio 6: la primera vez que se usa, trae lo que haya en los '
      'archivos viejos', () {
    test('trae los puntos sin enviar de cada recorrido, sin dueño, y luego '
        'borra sus archivos', () async {
      final viejos = archivosConUnRecorrido();
      final almacen = abrir(archivosViejos: viejos);

      expect(await almacen.conPendientes(), ['ent-viejo']);

      expect(await almacen.pendientes('ent-viejo'), [
        puntoPendienteDePrueba(orden: 1),
        puntoPendienteDePrueba(orden: 2),
      ]);
      // Directo de la tabla: la lista de la cuenta no muestra los sin dueño.
      final fila = await base
          .customSelect(
            "select usuario_id from recorridos_locales "
            "where entrenamiento_id = 'ent-viejo'",
          )
          .getSingle();
      expect(fila.data['usuario_id'], isNull);
      expect(viejos.olvidados, ['ent-viejo']);
      expect(await viejos.conPendientes(), isEmpty);
    });

    test('trae todos los recorridos viejos, no solo uno', () async {
      final viejos = archivosConUnRecorrido()
        ..sembrar('ent-viejo-2', [puntoPendienteDePrueba(orden: 0)]);
      final almacen = abrir(archivosViejos: viejos);

      expect(
        await almacen.conPendientes(),
        unorderedEquals(['ent-viejo', 'ent-viejo-2']),
      );
      expect(viejos.olvidados, unorderedEquals(['ent-viejo', 'ent-viejo-2']));
    });

    for (final (primerUso, usar)
        in <(String, Future<void> Function(AlmacenRecorrido))>[
          ('conPendientes', (almacen) => almacen.conPendientes()),
          ('pendientes', (almacen) => almacen.pendientes('ent-otro')),
          (
            'recorridosDeLaCuenta',
            (almacen) => almacen.recorridosDeLaCuenta().first,
          ),
          (
            'anadir',
            (almacen) =>
                almacen.anadir('ent-otro', puntoPendienteDePrueba(orden: 0)),
          ),
        ]) {
      test('importa en el primer uso, aunque sea $primerUso', () async {
        final viejos = archivosConUnRecorrido();
        final almacen = abrir(archivosViejos: viejos);

        await usar(almacen);

        expect(viejos.olvidados, ['ent-viejo']);
        expect(await almacen.pendientes('ent-viejo'), hasLength(2));
      });
    }

    test('importar dos veces lo mismo no duplica puntos', () async {
      // Como si los archivos no se hubieran podido borrar y la app se
      // volviera a abrir.
      await abrir(archivosViejos: archivosConUnRecorrido()).conPendientes();

      final reabierto = abrir(archivosViejos: archivosConUnRecorrido());

      expect(await reabierto.pendientes('ent-viejo'), hasLength(2));
      expect(await filas('puntos_locales'), 2);
    });

    test('si la importación falla, los archivos no se borran y nada '
        'revienta', () async {
      final viejos = archivosConUnRecorrido()
        ..error = Exception('disco no disponible');
      final almacen = abrir(archivosViejos: viejos);

      expect(await almacen.conPendientes(), isEmpty);

      // Y el almacén nuevo funciona igual.
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      expect(await almacen.pendientes('ent-1'), hasLength(1));
      viejos.error = null;
      expect(viejos.olvidados, isEmpty);
      expect(await viejos.pendientes('ent-viejo'), hasLength(2));
    });

    test('si un recorrido viejo no se puede leer, sus archivos no se borran '
        'y nada revienta', () async {
      final viejos = _ArchivosViejosQueFallan()
        ..sembrar('ent-malo', [puntoPendienteDePrueba(orden: 0)])
        ..ilegibles.add('ent-malo');
      final almacen = abrir(archivosViejos: viejos);

      await almacen.conPendientes();

      expect(viejos.olvidados, isNot(contains('ent-malo')));
      expect(viejos.guardados.keys, contains('ent-malo'));
    });

    test('si uno no se puede leer, los demás se importan igual', () async {
      final viejos = _ArchivosViejosQueFallan()
        ..sembrar('ent-a', [puntoPendienteDePrueba(orden: 0)])
        ..sembrar('ent-malo', [puntoPendienteDePrueba(orden: 0)])
        ..sembrar('ent-z', [puntoPendienteDePrueba(orden: 0)])
        ..ilegibles.add('ent-malo');
      final almacen = abrir(archivosViejos: viejos);

      expect(await almacen.conPendientes(), ['ent-a', 'ent-z']);
      expect(viejos.olvidados, containsAll(['ent-a', 'ent-z']));
    });

    test('si los archivos no se dejan borrar tras importarlos, nada revienta '
        'y lo importado se queda', () async {
      final viejos = _ArchivosViejosQueFallan()
        ..sembrar('ent-viejo', [
          for (var orden = 0; orden < 3; orden++)
            puntoPendienteDePrueba(orden: orden),
        ], enviados: 0)
        ..noSeDejanBorrar = true;
      final almacen = abrir(archivosViejos: viejos);

      await almacen.conPendientes();

      expect(await almacen.pendientes('ent-viejo'), hasLength(2));
    });
  });

  group('providers de la app', () {
    ProviderContainer crearContainer() {
      final container = ProviderContainer(
        overrides: [
          baseLocalProvider.overrideWithValue(base),
          usuarioActualProvider.overrideWithValue(() => usuario),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('criterio 1: almacenRecorridoProvider guarda en Drift, sobre la base '
        'local y con la cuenta con sesión', () async {
      final container = crearContainer();

      final almacen = container.read(almacenRecorridoProvider);
      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));

      expect(almacen, isA<AlmacenRecorridoDrift>());
      expect(await filas('puntos_locales'), 1);
      expect((await recorridoDe(almacen, 'ent-1')).usuarioId, 'uid-ana');
    });

    test('criterio 6: la app le pasa los archivos de antes para que los '
        'importe', () {
      final almacen =
          crearContainer().read(almacenRecorridoProvider)
              as AlmacenRecorridoDrift;

      expect(almacen.archivosViejos, isA<AlmacenRecorridoEnArchivos>());
    });

    test('criterio 5: recorridosLocalesProvider emite lo de la cuenta y se '
        'actualiza con cada cambio', () async {
      final container = crearContainer();
      container.listen(recorridosLocalesProvider, (_, _) {});
      final almacen = container.read(almacenRecorridoProvider);

      expect(await container.read(recorridosLocalesProvider.future), isEmpty);

      await almacen.anadir('ent-1', puntoPendienteDePrueba(orden: 0));
      await pumpEventQueue();

      final recorridos = container.read(recorridosLocalesProvider).value;
      expect(recorridos?.map((r) => r.entrenamientoId), ['ent-1']);
    });
  });
}

/// Archivos viejos que fallan donde la prueba diga: al leer un recorrido
/// concreto o al borrar cualquiera.
class _ArchivosViejosQueFallan extends AlmacenRecorridoFalso {
  /// Recorridos cuya lectura falla, como un archivo dañado.
  final Set<String> ilegibles = {};

  /// Si es `true`, borrar falla, como una carpeta sin permiso de escritura.
  bool noSeDejanBorrar = false;

  @override
  Future<List<PuntoPendiente>> pendientes(String entrenamientoId) async {
    if (ilegibles.contains(entrenamientoId)) {
      throw Exception('archivo ilegible');
    }
    return super.pendientes(entrenamientoId);
  }

  @override
  Future<void> olvidar(String entrenamientoId) async {
    if (noSeDejanBorrar) throw Exception('sin permiso para borrar');
    return super.olvidar(entrenamientoId);
  }
}
