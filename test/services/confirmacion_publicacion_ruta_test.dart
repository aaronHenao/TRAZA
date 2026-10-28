import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/rutas_repository_falso.dart';

/// El autor confirma la publicación de la ruta que un Runner Experto ya
/// clasificó (criterio 2 de SCRUM-363): qué devuelve, qué le dice y qué
/// refresca.
///
/// Quien decide si puede es `confirmar_publicacion_ruta` (0045); el doble
/// repite sus reglas.
void main() {
  late RutasRepositorioFalso repositorio;
  late ProviderContainer container;

  final clasificada = rutaDePrueba(
    autorId: 'autor-1',
    estado: EstadoRuta.clasificada,
    dificultad: Dificultad.moderada,
  );

  setUp(() {
    repositorio = RutasRepositorioFalso(
      rutas: [clasificada],
      usuario: 'autor-1',
    );
    container = ProviderContainer(
      overrides: [rutasRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoConfirmacionRuta> confirmar([Ruta? ruta]) => container
      .read(confirmacionPublicacionRutaProvider)
      .confirmar(ruta ?? clasificada);

  /// Deja cargados el detalle y las publicadas, con alguien escuchando como
  /// la pantalla (los dos son autoDispose).
  Future<void> conElDetalleYLasPublicadasCargados() async {
    container.listen(rutaProvider('ruta-1'), (_, _) {});
    container.listen(rutasPublicadasProvider, (_, _) {});
    expect(
      (await container.read(rutaProvider('ruta-1').future))?.estado,
      EstadoRuta.clasificada,
    );
    expect(await container.read(rutasPublicadasProvider.future), isEmpty);
  }

  test('al confirmar, TRAZA publica la ruta con el nivel de dificultad que '
      'le asigno el experto (criterio 2 de SCRUM-363)', () async {
    final resultado = await confirmar();

    final ruta = (resultado as RutaPublicadaConDificultad).ruta;
    expect(ruta.estado, EstadoRuta.publicada);
    expect(ruta.publicada, isTrue);
    expect(ruta.dificultad, Dificultad.moderada);
    expect(repositorio.confirmaciones, ['ruta-1']);
  });

  test(
    'publicada, el detalle y la lista de la comunidad ya la muestran',
    () async {
      await conElDetalleYLasPublicadasCargados();

      await confirmar();

      final detalle = await container.read(rutaProvider('ruta-1').future);
      expect(detalle?.estado, EstadoRuta.publicada);
      expect(detalle?.dificultad, Dificultad.moderada);
      final publicadas = await container.read(rutasPublicadasProvider.future);
      expect(publicadas.single.dificultad, Dificultad.moderada);
    },
  );

  test(
    'si no se publico, no vuelve a pedir ni el detalle ni la lista',
    () async {
      await conElDetalleYLasPublicadasCargados();
      final detalles = repositorio.consultasDeRuta;
      final listas = repositorio.consultasPublicadas;
      repositorio.errorConfirmacion = StateError('sin red');

      await confirmar();
      await container.read(rutaProvider('ruta-1').future);
      await container.read(rutasPublicadasProvider.future);

      expect(repositorio.consultasDeRuta, detalles);
      expect(repositorio.consultasPublicadas, listas);
    },
  );

  group('cuando la base dice que no', () {
    test('sin la dificultad asignada no se publica', () async {
      final enRevision = rutaDePrueba(autorId: 'autor-1');
      repositorio.rutas
        ..clear()
        ..add(enRevision);

      final resultado = await confirmar(enRevision);

      expect(
        (resultado as ConfirmacionNoGuardada).mensaje,
        ConfirmacionPublicacionRuta.yaCambio,
      );
      expect(repositorio.rutas.single.estado, EstadoRuta.enRevision);
    });

    test('nadie mas que el autor la publica', () async {
      repositorio.usuario = 'experto-1';

      final resultado = await confirmar();

      expect(
        (resultado as ConfirmacionNoGuardada).mensaje,
        ConfirmacionPublicacionRuta.sinPermiso,
      );
      expect(repositorio.rutas.single.estado, EstadoRuta.clasificada);
    });

    test('sin sesion pide iniciarla', () async {
      repositorio.usuario = null;

      final resultado = await confirmar();

      expect(
        (resultado as ConfirmacionNoGuardada).mensaje,
        ConfirmacionPublicacionRuta.sinSesion,
      );
    });

    test(
      'un fallo de red se dice sin el error crudo y deja reintentar',
      () async {
        repositorio.errorConfirmacion = StateError('sin red');

        final resultado = await confirmar();

        final mensaje = (resultado as ConfirmacionNoGuardada).mensaje;
        expect(mensaje, ConfirmacionPublicacionRuta.noSePudo);
        expect(mensaje, isNot(contains('sin red')));
        expect(repositorio.rutas.single.estado, EstadoRuta.clasificada);
      },
    );
  });
}
