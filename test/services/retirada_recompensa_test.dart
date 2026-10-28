import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/services/recompensas_provider.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas de la eliminación de recompensas (SCRUM-385): un retiro suave que
/// las saca del catálogo y de la gestión sin borrar la fila, para que los
/// canjes ya hechos sigan teniendo a qué apuntar.
void main() {
  final hidratacion = recompensaDePrueba(id: 'recompensa-hidratacion');
  final botella = recompensaDePrueba(
    id: 'recompensa-botella',
    nombre: 'Botella TRAZA',
    descripcion: 'Botella reutilizable de 750 ml.',
    puntos: 300,
  );
  final camiseta = recompensaDePrueba(
    id: 'recompensa-camiseta',
    nombre: 'Camiseta edición limitada',
    descripcion: 'Camiseta técnica con el logo de TRAZA.',
    puntos: 900,
    disponible: false,
  );

  late RecompensasRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = RecompensasRepositorioFalso(
      recompensas: [hidratacion, botella, camiseta],
    );
    container = ProviderContainer(
      overrides: [recompensasRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoRetiradaRecompensa> retirar(Recompensa recompensa) =>
      container.read(retiradaRecompensaProvider).retirar(recompensa);

  /// Deja abiertas y cargadas las dos listas, como si estuvieran en
  /// pantalla.
  Future<void> abrirListas() async {
    container.listen(catalogoRecompensasProvider, (_, _) {});
    container.listen(gestionRecompensasProvider, (_, _) {});
    await container.read(catalogoRecompensasProvider.future);
    await container.read(gestionRecompensasProvider.future);
  }

  Future<List<String>> idsDelCatalogo() async => [
    for (final r in await container.read(catalogoRecompensasProvider.future))
      r.id,
  ];

  Future<List<String>> idsDeLaGestion() async => [
    for (final r in await container.read(gestionRecompensasProvider.future))
      r.id,
  ];

  group('eliminación confirmada (criterio 2 de SCRUM-385)', () {
    // Que la fila se quede para el historial (criterio 3) lo garantizan el
    // PATCH del repositorio (recompensas_service_test) y el script de 0039.
    test(
      'la recompensa elegida queda retirada (criterio 2 de SCRUM-385)',
      () async {
        final resultado = await retirar(hidratacion);

        expect(resultado, isA<RecompensaRetirada>());
        expect(repositorio.retiradas, contains('recompensa-hidratacion'));
      },
    );

    test('se retira la recompensa que se eligió, y solo esa', () async {
      await retirar(hidratacion);

      expect(repositorio.recompensaRetirada?.id, 'recompensa-hidratacion');
      expect(repositorio.retiradas, {'recompensa-hidratacion'});
    });

    test('el catálogo del corredor y la gestión se vuelven a consultar y ya '
        'no la traen; las demás siguen', () async {
      await abrirListas();
      expect(await idsDelCatalogo(), contains('recompensa-hidratacion'));
      expect(await idsDeLaGestion(), contains('recompensa-hidratacion'));
      final consultasCatalogo = repositorio.consultasCatalogo;
      final consultasTodas = repositorio.consultasTodas;

      await retirar(hidratacion);

      final catalogo = await idsDelCatalogo();
      final gestion = await idsDeLaGestion();
      expect(repositorio.consultasCatalogo, greaterThan(consultasCatalogo));
      expect(repositorio.consultasTodas, greaterThan(consultasTodas));
      expect(catalogo, ['recompensa-botella']);
      expect(gestion, isNot(contains('recompensa-hidratacion')));
      expect(
        gestion,
        containsAll(['recompensa-botella', 'recompensa-camiseta']),
      );
    });

    test('una recompensa no disponible también se puede eliminar, y sale de '
        'la gestión', () async {
      await abrirListas();

      final resultado = await retirar(camiseta);

      expect(resultado, isA<RecompensaRetirada>());
      expect(repositorio.recompensaRetirada?.id, 'recompensa-camiseta');
      expect(await idsDeLaGestion(), isNot(contains('recompensa-camiseta')));
      // Lo que ve el corredor no cambia: esa ya no le aparecía.
      expect(await idsDelCatalogo(), [
        'recompensa-hidratacion',
        'recompensa-botella',
      ]);
    });
  });

  group('cuando no se puede eliminar', () {
    test('sin sesión se pide iniciarla', () async {
      repositorio.error = const SesionRequeridaParaRecompensasException();

      final resultado = await retirar(hidratacion);

      expect(resultado, isA<RecompensaNoRetirada>());
      expect(
        (resultado as RecompensaNoRetirada).mensaje,
        RetiradaRecompensa.sinSesion,
      );
    });

    test('quien no es administrador no elimina nada', () async {
      // Es lo que llega cuando la policy de update, que exige es_admin(),
      // niega el cambio o no deja ver la fila (PGRST116).
      repositorio.error = const SoloAdministradorException();

      final resultado = await retirar(hidratacion) as RecompensaNoRetirada;

      expect(resultado.mensaje, RetiradaRecompensa.soloAdministrador);
    });

    test('un fallo de red se traduce a un mensaje reintentable', () async {
      repositorio.error = Exception('sin conexión');

      final resultado = await retirar(hidratacion) as RecompensaNoRetirada;

      expect(resultado.mensaje, RetiradaRecompensa.noSePudo);
    });

    test('si no se eliminó, el catálogo y la gestión se quedan como estaban: '
        'ni siquiera se vuelven a consultar', () async {
      await abrirListas();
      final consultasCatalogo = repositorio.consultasCatalogo;
      final consultasTodas = repositorio.consultasTodas;
      repositorio.error = Exception('sin conexión');

      await retirar(hidratacion);
      // Vuelve la conexión: si alguien invalidó las listas, se notaría en
      // las consultas.
      repositorio.error = null;

      expect(await idsDelCatalogo(), contains('recompensa-hidratacion'));
      expect(await idsDeLaGestion(), contains('recompensa-hidratacion'));
      expect(repositorio.consultasCatalogo, consultasCatalogo);
      expect(repositorio.consultasTodas, consultasTodas);
      expect(repositorio.retiradas, isEmpty);
    });

    test('los mensajes son los acordados, sin texto crudo de la base', () {
      expect(
        RetiradaRecompensa.sinSesion,
        'Inicia sesión para eliminar recompensas.',
      );
      expect(
        RetiradaRecompensa.soloAdministrador,
        'Solo el administrador puede eliminar recompensas.',
      );
      expect(
        RetiradaRecompensa.noSePudo,
        'No se pudo eliminar la recompensa. Inténtalo de nuevo.',
      );
    });
  });
}
