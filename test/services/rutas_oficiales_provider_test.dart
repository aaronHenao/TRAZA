import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_oficial.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;
import 'package:traza/services/rutas_oficiales_provider.dart';
import 'package:traza/services/rutas_oficiales_service.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/rutas_oficiales_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Lo que la app hace al gestionar las rutas oficiales (rutas oficiales,
/// etapa 1): qué ofrece para agregar, qué posición pide al mover y qué le
/// dice al administrador cuando la base no deja.
void main() {
  final estadio = rutaDePrueba(
    id: 'ruta-estadio',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    dificultad: Dificultad.facil,
  );
  final nutibara = rutaDePrueba(
    id: 'ruta-nutibara',
    nombre: 'Cerro Nutibara',
    autorNombre: 'Luis',
    estado: EstadoRuta.publicada,
    distanciaKm: 7.5,
    dificultad: Dificultad.dificil,
  );
  final rio = rutaDePrueba(
    id: 'ruta-rio',
    nombre: 'Parque del río',
    autorNombre: 'Sara',
    estado: EstadoRuta.publicada,
    distanciaKm: 3,
  );
  final circuito = rutaDePrueba(
    id: 'ruta-circuito',
    nombre: 'Circuito universitario',
    estado: EstadoRuta.publicada,
  );
  final enRevision = rutaDePrueba(
    id: 'ruta-en-revision',
    nombre: 'Todavía en revisión',
  );
  final todas = [estadio, nutibara, rio, circuito, enRevision];

  late RutasOficialesRepositorioFalso oficiales;
  late RutasRepositorioFalso rutas;
  late ProviderContainer container;

  void montar({List<Ruta>? enElCamino, List<Ruta>? enLaTabla}) {
    final tabla = enLaTabla ?? todas;
    oficiales = RutasOficialesRepositorioFalso(
      oficiales: enElCamino ?? [estadio, nutibara],
      rutas: tabla,
    );
    rutas = RutasRepositorioFalso(rutas: tabla);
    container = ProviderContainer(
      overrides: [
        rutasOficialesRepositoryProvider.overrideWithValue(oficiales),
        rutasRepositoryProvider.overrideWithValue(rutas),
      ],
    );
    addTearDown(container.dispose);
  }

  GestionRutasOficiales gestion() =>
      container.read(gestionRutasOficialesProvider);

  Future<List<RutaOficial>> camino() =>
      container.read(rutasOficialesProvider.future);

  Future<List<String>> idsDelCamino() async => [
    for (final oficial in await camino()) oficial.ruta.id,
  ];

  Future<List<String>> idsCandidatas() async => [
    for (final ruta in await container.read(
      candidatasRutaOficialProvider.future,
    ))
      ruta.id,
  ];

  Future<RutaOficial> oficial(String id) async =>
      (await camino()).firstWhere((o) => o.ruta.id == id);

  /// Deja abiertas y cargadas la lista y las candidatas, como si estuvieran
  /// en pantalla.
  Future<void> abrirListas() async {
    container.listen(rutasOficialesProvider, (_, _) {});
    container.listen(candidatasRutaOficialProvider, (_, _) {});
    await camino();
    await container.read(candidatasRutaOficialProvider.future);
  }

  group('la lista (criterio 2)', () {
    test('trae las rutas oficiales en el orden del camino', () async {
      montar(enElCamino: [nutibara, estadio, rio]);

      final lista = await camino();

      expect(lista.map((o) => o.posicion), [1, 2, 3]);
      expect(lista.map((o) => o.ruta.id), [
        'ruta-nutibara',
        'ruta-estadio',
        'ruta-rio',
      ]);
    });

    test('sin rutas oficiales, la lista está vacía', () async {
      montar(enElCamino: []);

      expect(await camino(), isEmpty);
    });
  });

  group('candidatas para agregar (criterio 3)', () {
    test('ofrece las publicadas que todavía no son oficiales', () async {
      montar();

      expect(await idsCandidatas(), ['ruta-rio', 'ruta-circuito']);
    });

    test('no ofrece las que no están publicadas', () async {
      montar();

      expect(await idsCandidatas(), isNot(contains('ruta-en-revision')));
    });

    test('sin rutas oficiales, ofrece todas las publicadas', () async {
      montar(enElCamino: []);

      expect(await idsCandidatas(), [
        'ruta-estadio',
        'ruta-nutibara',
        'ruta-rio',
        'ruta-circuito',
      ]);
    });

    test(
      'si todas las publicadas ya son oficiales, no ofrece ninguna',
      () async {
        montar(enElCamino: [estadio, nutibara, rio, circuito]);

        expect(await idsCandidatas(), isEmpty);
      },
    );

    test('si no hay rutas publicadas, no ofrece ninguna', () async {
      montar(enElCamino: [], enLaTabla: [enRevision]);

      expect(await idsCandidatas(), isEmpty);
    });
  });

  group('agregar (criterio 3)', () {
    test('agrega la ruta elegida y no devuelve mensaje de error', () async {
      montar();

      final mensaje = await gestion().agregar(rio);

      expect(mensaje, isNull);
      expect(oficiales.agregadas, ['ruta-rio']);
    });

    test('la lista se vuelve a consultar con la nueva al final, y deja de '
        'ser candidata', () async {
      montar();
      await abrirListas();
      final consultas = oficiales.consultas;

      await gestion().agregar(rio);

      expect(await idsDelCamino(), [
        'ruta-estadio',
        'ruta-nutibara',
        'ruta-rio',
      ]);
      expect((await oficial('ruta-rio')).posicion, 3);
      expect(oficiales.consultas, greaterThan(consultas));
      expect(await idsCandidatas(), ['ruta-circuito']);
    });
  });

  group('subir y bajar (criterio 4)', () {
    test('subir pide la posición anterior: la 2 pasa a la 1', () async {
      montar();

      final mensaje = await gestion().subir(await oficial('ruta-nutibara'));

      expect(mensaje, isNull);
      expect(oficiales.movimientos, [('ruta-nutibara', 1)]);
    });

    test('bajar pide la posición siguiente: la 1 pasa a la 2', () async {
      montar();

      final mensaje = await gestion().bajar(await oficial('ruta-estadio'));

      expect(mensaje, isNull);
      expect(oficiales.movimientos, [('ruta-estadio', 2)]);
    });

    test('desde el medio del camino, subir y bajar piden la vecina de cada '
        'lado', () async {
      montar(enElCamino: [estadio, nutibara, rio]);

      await gestion().subir(await oficial('ruta-nutibara'));
      oficiales.movimientos.clear();
      // Ahora el Nutibara es la 1 y el estadio la 2.
      await gestion().bajar(await oficial('ruta-estadio'));

      expect(oficiales.movimientos, [('ruta-estadio', 3)]);
    });

    test('después de mover, la lista se vuelve a consultar con el orden '
        'nuevo', () async {
      montar();
      await abrirListas();
      final consultas = oficiales.consultas;

      await gestion().subir(await oficial('ruta-nutibara'));

      expect(await idsDelCamino(), ['ruta-nutibara', 'ruta-estadio']);
      expect(oficiales.consultas, greaterThan(consultas));
      expect((await oficial('ruta-nutibara')).posicion, 1);
    });
  });

  group('quitar (criterio 5)', () {
    test('quita la ruta elegida y no devuelve mensaje de error', () async {
      montar();

      final mensaje = await gestion().quitar(await oficial('ruta-estadio'));

      expect(mensaje, isNull);
      expect(oficiales.quitadas, ['ruta-estadio']);
    });

    test('la lista se vuelve a consultar sin ella, y vuelve a ser '
        'candidata', () async {
      montar();
      await abrirListas();
      final consultas = oficiales.consultas;

      await gestion().quitar(await oficial('ruta-estadio'));

      expect(await idsDelCamino(), ['ruta-nutibara']);
      expect(oficiales.consultas, greaterThan(consultas));
      expect((await oficial('ruta-nutibara')).posicion, 1);
      expect(await idsCandidatas(), contains('ruta-estadio'));
    });
  });

  group('cuando la base no deja (criterio 6)', () {
    final acciones =
        <
          (String, Future<String?> Function(GestionRutasOficiales, RutaOficial))
        >[
          ('agregar', (g, o) => g.agregar(o.ruta)),
          ('subir', (g, o) => g.subir(o)),
          ('bajar', (g, o) => g.bajar(o)),
          ('quitar', (g, o) => g.quitar(o)),
        ];

    final errores = <(String, Object, String)>[
      (
        'SoloAdministradorException',
        const SoloAdministradorException(),
        GestionRutasOficiales.soloAdministrador,
      ),
      (
        'RutaNoPublicadaException',
        const RutaNoPublicadaException(),
        GestionRutasOficiales.noPublicada,
      ),
      (
        'RutaYaOficialException',
        const RutaYaOficialException(),
        GestionRutasOficiales.yaOficial,
      ),
      // Otra pestaña ya la quitó del mapa (TZ404 en mover y quitar).
      (
        'RutaNoOficialException',
        const RutaNoOficialException(),
        GestionRutasOficiales.noOficial,
      ),
      (
        'cualquier otro error',
        Exception('Failed host lookup: proyecto.supabase.co'),
        GestionRutasOficiales.noSePudo,
      ),
    ];

    for (final (accion, ejecutar) in acciones) {
      for (final (nombre, error, mensaje) in errores) {
        test(
          '$accion: si el repositorio lanza $nombre, devuelve "$mensaje"',
          () async {
            montar();
            final elegida = await oficial('ruta-nutibara');
            oficiales.errorAlCambiar = error;

            final devuelto = await ejecutar(gestion(), elegida);

            expect(devuelto, mensaje);
            // Nada del error crudo llega al usuario.
            expect(devuelto, isNot(contains('Exception')));
            expect(devuelto, isNot(contains('supabase.co')));
          },
        );
      }
    }

    test('aunque falle, la lista y las candidatas se vuelven a consultar: '
        'la base pudo haber cambiado por otro lado', () async {
      montar();
      await abrirListas();
      final consultas = oficiales.consultas;
      final publicadas = rutas.consultasPublicadas;
      oficiales.errorAlCambiar = const RutaYaOficialException();

      await gestion().agregar(rio);
      await camino();
      await container.read(candidatasRutaOficialProvider.future);

      expect(oficiales.consultas, greaterThan(consultas));
      expect(rutas.consultasPublicadas, greaterThan(publicadas));
    });

    test('si falla, el camino queda como estaba', () async {
      montar();
      oficiales.errorAlCambiar = const SoloAdministradorException();

      await gestion().quitar(await oficial('ruta-estadio'));
      oficiales.errorAlCambiar = null;

      expect(await idsDelCamino(), ['ruta-estadio', 'ruta-nutibara']);
    });

    test('los mensajes son los acordados, sin texto crudo de la base', () {
      expect(
        GestionRutasOficiales.soloAdministrador,
        'Solo el administrador gestiona las rutas oficiales',
      );
      expect(
        GestionRutasOficiales.noPublicada,
        'Esa ruta ya no está publicada',
      );
      expect(GestionRutasOficiales.yaOficial, 'Esa ruta ya es oficial');
      expect(GestionRutasOficiales.noOficial, 'Esa ruta ya no está en el mapa');
      expect(GestionRutasOficiales.noSePudo, 'No se pudo guardar el cambio');
    });
  });
}
