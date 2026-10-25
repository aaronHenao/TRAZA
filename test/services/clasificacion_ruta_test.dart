import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/rutas_repository_falso.dart';

/// Un Runner Experto le asigna la dificultad a una ruta en revisión
/// (SCRUM-363): qué devuelve, qué le dice y qué refresca.
///
/// Quien decide si puede es `clasificar_ruta` (0045); el doble repite sus
/// reglas para que aquí se pruebe cómo la app traduce cada respuesta.
void main() {
  late RutasRepositorioFalso repositorio;
  late ProviderContainer container;

  final enRevision = rutaDePrueba(autorId: 'autor-1');

  setUp(() {
    repositorio = RutasRepositorioFalso(
      rutas: [enRevision],
      usuario: 'experto-1',
    );
    container = ProviderContainer(
      overrides: [rutasRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoClasificacionRuta> clasificar([
    Dificultad dificultad = Dificultad.moderada,
  ]) => container
      .read(clasificacionRutaProvider)
      .clasificar(enRevision, dificultad);

  /// Deja cargadas la bandeja y el detalle, con alguien escuchando como la
  /// pantalla: los dos son autoDispose y sin suscripción se tirarían entre
  /// lecturas, refrescando por su cuenta y sin probar nada.
  Future<void> conLaBandejaYElDetalleCargados() async {
    container.listen(rutasPorClasificarProvider, (_, _) {});
    container.listen(rutaProvider('ruta-1'), (_, _) {});
    expect(await container.read(rutasPorClasificarProvider.future), [
      enRevision,
    ]);
    expect(
      (await container.read(rutaProvider('ruta-1').future))?.estado,
      EstadoRuta.enRevision,
    );
  }

  test('el experto asigna la dificultad y la ruta queda clasificada, '
      'esperando al autor (SCRUM-363)', () async {
    final resultado = await clasificar();

    final ruta = (resultado as RutaClasificada).ruta;
    expect(ruta.estado, EstadoRuta.clasificada);
    expect(ruta.dificultad, Dificultad.moderada);
    expect(repositorio.clasificaciones, [
      (rutaId: 'ruta-1', dificultad: Dificultad.moderada),
    ]);
  });

  test(
    'clasificada, sale de la bandeja y su detalle ya trae la dificultad',
    () async {
      await conLaBandejaYElDetalleCargados();

      await clasificar();

      // Sin que nadie vuelva a entrar: lo piden los providers al quedar
      // invalidados.
      expect(await container.read(rutasPorClasificarProvider.future), isEmpty);
      final detalle = await container.read(rutaProvider('ruta-1').future);
      expect(detalle?.estado, EstadoRuta.clasificada);
      expect(detalle?.dificultad, Dificultad.moderada);
    },
  );

  test(
    'si no se guardo, no vuelve a pedir ni la bandeja ni el detalle',
    () async {
      await conLaBandejaYElDetalleCargados();
      final bandejas = repositorio.consultasPorClasificar;
      final detalles = repositorio.consultasDeRuta;
      repositorio.errorClasificacion = StateError('sin red');

      await clasificar();
      await container.read(rutasPorClasificarProvider.future);
      await container.read(rutaProvider('ruta-1').future);

      expect(repositorio.consultasPorClasificar, bandejas);
      expect(repositorio.consultasDeRuta, detalles);
    },
  );

  group('cuando la base dice que no', () {
    test('un experto no clasifica su propia ruta', () async {
      repositorio.usuario = 'autor-1';

      final resultado = await clasificar();

      expect(
        (resultado as ClasificacionNoGuardada).mensaje,
        ClasificacionRuta.sinPermiso,
      );
      expect(repositorio.rutas.single.estado, EstadoRuta.enRevision);
    });

    test('un corredor sin el rol tampoco', () async {
      // 42501 de `clasificar_ruta`: `es_experto()` dijo que no.
      repositorio.errorClasificacion = const SinPermisoSobreRutaException();

      final resultado = await clasificar();

      expect(
        (resultado as ClasificacionNoGuardada).mensaje,
        ClasificacionRuta.sinPermiso,
      );
    });

    test(
      'si otro experto se adelanto, dice que ya no esta en revision',
      () async {
        repositorio.usuario = 'otro-experto';
        await clasificar(Dificultad.facil);
        repositorio.usuario = 'experto-1';

        final resultado = await clasificar();

        expect(
          (resultado as ClasificacionNoGuardada).mensaje,
          ClasificacionRuta.yaCambio,
        );
        // Se queda con la del primero.
        expect(repositorio.rutas.single.dificultad, Dificultad.facil);
      },
    );

    test('sin sesion pide iniciarla', () async {
      repositorio.usuario = null;

      final resultado = await clasificar();

      expect(
        (resultado as ClasificacionNoGuardada).mensaje,
        ClasificacionRuta.sinSesion,
      );
    });

    test(
      'un fallo de red se dice sin el error crudo y deja reintentar',
      () async {
        repositorio.errorClasificacion = StateError('sin red');

        final resultado = await clasificar();

        final mensaje = (resultado as ClasificacionNoGuardada).mensaje;
        expect(mensaje, ClasificacionRuta.noSePudo);
        expect(mensaje, isNot(contains('sin red')));
      },
    );
  });
}
