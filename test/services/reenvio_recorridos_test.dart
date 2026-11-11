import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/recorrido_local.dart';
import 'package:traza/models/verificacion_ruta.dart';
import 'package:traza/services/almacen_recorrido.dart';
import 'package:traza/services/mapa_progresion_provider.dart';
import 'package:traza/services/recorrido_provider.dart'
    show repositorioPuntosGpsProvider;
import 'package:traza/services/reenvio_recorridos.dart';
import 'package:traza/services/rutas_oficiales_service.dart';

import '../utiles/almacen_recorrido_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';
import '../utiles/rutas_oficiales_repository_falso.dart';

/// Subir al abrir la app lo que quedó sin enviar (SCRUM-292).
///
/// Es lo que cierra la deuda: sin esto, un recorrido que se quedó en disco
/// porque la red no volvió antes de cerrar la app se quedaría ahí para
/// siempre.
///
/// Desde rutas oficiales, etapa 4, al terminar de subir un recorrido se
/// vuelve a pedir la verificación de su ruta: con puntos que faltaban, la
/// del resumen pudo dar una cobertura baja.
///
/// Desde Drift (Desarrollo Móvil), lo que la base rechaza ya no se borra: se
/// anota el motivo y se deja de reintentar, para que la pantalla de
/// sincronización pueda mostrarlo.
void main() {
  late AlmacenRecorridoFalso almacen;
  late RepositorioPuntosGpsFalso repositorio;
  late RutasOficialesRepositorioFalso rutasOficiales;
  late ProviderContainer container;

  setUp(() {
    almacen = AlmacenRecorridoFalso();
    repositorio = RepositorioPuntosGpsFalso();
    rutasOficiales = RutasOficialesRepositorioFalso();
    container = ProviderContainer(
      overrides: [
        almacenRecorridoProvider.overrideWithValue(almacen),
        repositorioPuntosGpsProvider.overrideWithValue(repositorio),
        // La verificación de la ruta nunca va a la base real (etapa 4).
        rutasOficialesRepositoryProvider.overrideWithValue(rutasOficiales),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<int> reintentar() => container.read(reenvioRecorridosProvider.future);

  /// Un recorrido que quedó a medio subir en una sesión anterior.
  void dejarPendiente(
    String entrenamientoId,
    int cuantos, {
    int enviados = -1,
  }) {
    almacen.sembrar(entrenamientoId, [
      for (var orden = 0; orden < cuantos; orden++)
        puntoPendienteDePrueba(orden: orden),
    ], enviados: enviados);
  }

  test('sin nada pendiente no toca la red', () async {
    expect(await reintentar(), 0);

    expect(repositorio.intentos, 0);
  });

  test('sube lo que quedó de una sesión anterior', () async {
    dejarPendiente('ent-1', 12);

    expect(await reintentar(), 1);

    expect(repositorio.puntosDe('ent-1'), hasLength(12));
  });

  test('solo sube lo que la base no tenía ya', () async {
    // Los 8 primeros entraron antes de que se cayera la red.
    dejarPendiente('ent-1', 12, enviados: 7);

    await reintentar();

    expect(repositorio.lotes.single.ordenes, [8, 9, 10, 11]);
  });

  test('una vez subido, deja de ocupar el disco', () async {
    dejarPendiente('ent-1', 5);

    await reintentar();

    expect(almacen.olvidados, ['ent-1']);
    expect(await almacen.conPendientes(), isEmpty);
  });

  test('sube todos los recorridos que haya, no solo el último', () async {
    dejarPendiente('ent-1', 3);
    dejarPendiente('ent-2', 4);

    expect(await reintentar(), 2);

    expect(repositorio.puntosDe('ent-1'), hasLength(3));
    expect(repositorio.puntosDe('ent-2'), hasLength(4));
  });

  test(
    'si la red sigue caída, el recorrido se queda para la próxima',
    () async {
      dejarPendiente('ent-1', 5);
      repositorio.fallar = true;

      expect(await reintentar(), 0);

      // Lo importante: no se borró.
      expect(almacen.olvidados, isEmpty);
      expect(await almacen.pendientes('ent-1'), hasLength(5));
    },
  );

  test('si no se puede ni mirar el disco, no revienta la portada', () async {
    almacen.error = Exception('disco no disponible');

    expect(await reintentar(), 0);
  });

  group('criterio 4 (Drift, Desarrollo Móvil): si no se pudo enviar, se '
      'anota el motivo sin borrar nada', () {
    // Antes, lo rechazado (42501/23503) se borraba del disco. Ahora se
    // conserva con su motivo y se deja de reintentar solo.
    test('ante un 23503 (el entrenamiento ya no existe) anota motivoRechazado '
        'como rechazado y no borra los puntos', () async {
      dejarPendiente('ent-borrado', 5);
      repositorio.fallar = true;
      // 23503: la clave foránea no encuentra el entrenamiento.
      repositorio.error = const PostgrestException(
        message: 'insert or update violates foreign key constraint',
        code: '23503',
      );

      expect(await reintentar(), 0);

      expect(almacen.errores, [
        (
          entrenamientoId: 'ent-borrado',
          motivo: RecorridoLocal.motivoRechazado,
          rechazado: true,
        ),
      ]);
      expect(almacen.olvidados, isEmpty);
      expect(await almacen.pendientes('ent-borrado'), hasLength(5));
    });

    test('ante un 42501 (es de otra cuenta) anota motivoRechazado como '
        'rechazado y no borra los puntos', () async {
      dejarPendiente('ent-ajeno', 5);
      repositorio.fallar = true;
      // 42501: la policy no deja escribir en ese entrenamiento.
      repositorio.error = const PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      );

      await reintentar();

      expect(almacen.errores, [
        (
          entrenamientoId: 'ent-ajeno',
          motivo: RecorridoLocal.motivoRechazado,
          rechazado: true,
        ),
      ]);
      expect(almacen.olvidados, isEmpty);
      expect(await almacen.pendientes('ent-ajeno'), hasLength(5));
    });

    test('un recorrido rechazado ya no se reintenta solo en el próximo '
        'arranque', () async {
      dejarPendiente('ent-borrado', 5);
      repositorio
        ..fallar = true
        ..error = const PostgrestException(
          message: 'insert or update violates foreign key constraint',
          code: '23503',
        );
      await reintentar();
      repositorio.fallar = false;

      // El siguiente arranque.
      expect(await container.refresh(reenvioRecorridosProvider.future), 0);

      expect(repositorio.intentos, 1);
    });

    test('ante cualquier otro error anota motivoSinEnviar, sin marcarlo '
        'rechazado ni borrar nada', () async {
      dejarPendiente('ent-1', 5);
      repositorio.fallar = true;

      expect(await reintentar(), 0);

      expect(almacen.errores, [
        (
          entrenamientoId: 'ent-1',
          motivo: RecorridoLocal.motivoSinEnviar,
          rechazado: false,
        ),
      ]);
      expect(almacen.olvidados, isEmpty);
      expect(await almacen.pendientes('ent-1'), hasLength(5));
    });

    test('un error de la base con otro código no cuenta como '
        'rechazo', () async {
      dejarPendiente('ent-1', 5);
      repositorio
        ..fallar = true
        // 57014: la consulta tardó demasiado. Reintentarlo puede salir bien.
        ..error = const PostgrestException(
          message: 'canceling statement due to statement timeout',
          code: '57014',
        );

      await reintentar();

      expect(almacen.errores.single.motivo, RecorridoLocal.motivoSinEnviar);
      expect(almacen.errores.single.rechazado, isFalse);
    });

    test('lo que falló por otra causa se reintenta en el próximo arranque y '
        'sube', () async {
      dejarPendiente('ent-1', 5);
      repositorio.fallar = true;
      await reintentar();
      repositorio.fallar = false;

      // El siguiente arranque, ya con red.
      expect(await container.refresh(reenvioRecorridosProvider.future), 1);

      expect(repositorio.puntosDe('ent-1'), hasLength(5));
    });

    for (final (causa, error, motivo) in [
      (
        'la base lo rechaza',
        const PostgrestException(
          message:
              'new row violates row-level security policy for table '
              '"puntos_gps"',
          code: '42501',
        ),
        RecorridoLocal.motivoRechazado,
      ),
      (
        'se cae la red',
        StateError('SocketException: Failed host lookup "puntos_gps"'),
        RecorridoLocal.motivoSinEnviar,
      ),
    ]) {
      test('si $causa, el motivo anotado es el texto fijo, nunca el error '
          'crudo', () async {
        dejarPendiente('ent-1', 5);
        repositorio
          ..fallar = true
          ..error = error;

        await reintentar();

        final anotado = almacen.errores.single.motivo;
        expect(anotado, motivo);
        expect(anotado, isNot(contains('puntos_gps')));
      });
    }

    test('si ni siquiera se puede anotar el motivo, no revienta la '
        'portada', () async {
      dejarPendiente('ent-1', 5);
      repositorio.fallar = true;
      almacen.errorAlRegistrar = Exception('disco lleno');

      expect(await reintentar(), 0);

      expect(await almacen.pendientes('ent-1'), hasLength(5));
    });

    test('si ni siquiera se puede anotar el rechazo, no revienta la portada '
        'ni borra nada', () async {
      dejarPendiente('ent-borrado', 5);
      repositorio
        ..fallar = true
        ..error = const PostgrestException(
          message: 'insert or update violates foreign key constraint',
          code: '23503',
        );
      almacen.errorAlRegistrar = Exception('disco lleno');

      expect(await reintentar(), 0);

      expect(almacen.olvidados, isEmpty);
      expect(await almacen.pendientes('ent-borrado'), hasLength(5));
    });
  });

  group('verificar la ruta al terminar de subir (rutas oficiales, etapa 4, '
      'criterio 5)', () {
    test('al subir del todo un recorrido pendiente, pide verificar su '
        'ruta', () async {
      dejarPendiente('ent-1', 12);
      rutasOficiales.verificacion = const VerificacionRuta(
        cobertura: 0.95,
        necesaria: 0.9,
        completada: true,
      );

      expect(await reintentar(), 1);

      expect(rutasOficiales.verificados, ['ent-1']);
    });

    test('si la base dice que la completó, el mapa abierto se vuelve a '
        'consultar y avanza', () async {
      container.listen(mapaProgresionProvider, (_, _) {});
      await container.read(mapaProgresionProvider.future);
      final antes = rutasOficiales.consultasCompletadas;
      dejarPendiente('ent-1', 12);
      rutasOficiales.verificacion = const VerificacionRuta(
        cobertura: 0.95,
        necesaria: 0.9,
        completada: true,
      );

      await reintentar();
      await container.read(mapaProgresionProvider.future);

      expect(rutasOficiales.consultasCompletadas, antes + 1);
    });

    test('si no la completó, el mapa no se vuelve a consultar', () async {
      container.listen(mapaProgresionProvider, (_, _) {});
      await container.read(mapaProgresionProvider.future);
      final antes = rutasOficiales.consultasCompletadas;
      dejarPendiente('ent-1', 12);
      rutasOficiales.verificacion = const VerificacionRuta(
        cobertura: 0.5,
        necesaria: 0.9,
        completada: false,
      );

      await reintentar();
      await container.read(mapaProgresionProvider.future);

      expect(rutasOficiales.consultasCompletadas, antes);
    });

    test('verifica cada recorrido que termina de subir', () async {
      dejarPendiente('ent-1', 3);
      dejarPendiente('ent-2', 4);

      expect(await reintentar(), 2);

      expect(rutasOficiales.verificados, ['ent-1', 'ent-2']);
    });

    test('verifica con todo el recorrido ya en la base, no antes de '
        'subirlo', () async {
      // Verificar antes de subir daría la misma cobertura baja del resumen.
      final mirona = _VerificacionQueMiraLaBase(repositorio);
      final conMirona = ProviderContainer(
        overrides: [
          almacenRecorridoProvider.overrideWithValue(almacen),
          repositorioPuntosGpsProvider.overrideWithValue(repositorio),
          rutasOficialesRepositoryProvider.overrideWithValue(mirona),
        ],
      );
      addTearDown(conMirona.dispose);
      dejarPendiente('ent-1', 12);

      expect(await conMirona.read(reenvioRecorridosProvider.future), 1);

      expect(mirona.verificados, ['ent-1']);
      expect(mirona.puntosAlVerificar, {'ent-1': 12});
    });

    test('también verifica si la base ya tenía todos los puntos y solo '
        'faltaba olvidarlo del disco', () async {
      // Todo entró antes de cerrar la app, pero no alcanzó a borrarse.
      dejarPendiente('ent-1', 5, enviados: 4);

      expect(await reintentar(), 1);

      expect(repositorio.intentos, 0);
      expect(rutasOficiales.verificados, ['ent-1']);
    });

    test('si la subida falla, no se verifica', () async {
      dejarPendiente('ent-1', 5);
      repositorio.fallar = true;

      expect(await reintentar(), 0);

      expect(rutasOficiales.verificados, isEmpty);
    });

    test('un recorrido rechazado (ya no existe o es de otro) no se '
        'verifica', () async {
      dejarPendiente('ent-borrado', 5);
      repositorio
        ..fallar = true
        ..error = const PostgrestException(
          message: 'insert or update violates foreign key constraint',
          code: '23503',
        );

      expect(await reintentar(), 0);

      // Desde Drift (Desarrollo Móvil) lo rechazado ya no se borra.
      expect(almacen.olvidados, isEmpty);
      expect(rutasOficiales.verificados, isEmpty);
    });

    for (final (causa, error) in [
      ('se cae la red', StateError('Supabase no disponible')),
      ('el recorrido no es válido', const RecorridoNoValidoException()),
      ('la ruta ya no es oficial', const RutaNoOficialException()),
      (
        'la base lo niega',
        const PostgrestException(message: 'permission denied', code: '42501'),
      ),
    ]) {
      test('si la verificación falla porque $causa, el recorrido cuenta como '
          'subido y no vuelve al disco', () async {
        dejarPendiente('ent-1', 5);
        rutasOficiales.errorAlVerificar = error;

        expect(await reintentar(), 1);

        expect(rutasOficiales.verificados, ['ent-1']);
        expect(repositorio.puntosDe('ent-1'), hasLength(5));
        expect(almacen.olvidados, ['ent-1']);
        expect(await almacen.conPendientes(), isEmpty);
      });
    }

    test('si falla la verificación del primero, los demás se suben y se '
        'verifican igual', () async {
      dejarPendiente('ent-1', 3);
      dejarPendiente('ent-2', 4);
      rutasOficiales.errorAlVerificar = StateError('Supabase no disponible');

      expect(await reintentar(), 2);

      expect(rutasOficiales.verificados, ['ent-1', 'ent-2']);
      expect(repositorio.puntosDe('ent-2'), hasLength(4));
      expect(almacen.olvidados, ['ent-1', 'ent-2']);
    });
  });
}

/// Anota cuántos puntos del entrenamiento había en la base en el momento
/// en que se pidió verificar su ruta.
class _VerificacionQueMiraLaBase extends RutasOficialesRepositorioFalso {
  _VerificacionQueMiraLaBase(this._puntos);

  final RepositorioPuntosGpsFalso _puntos;

  final puntosAlVerificar = <String, int>{};

  @override
  Future<VerificacionRuta?> verificar(String entrenamientoId) {
    puntosAlVerificar[entrenamientoId] = _puntos
        .puntosDe(entrenamientoId)
        .length;
    return super.verificar(entrenamientoId);
  }
}
