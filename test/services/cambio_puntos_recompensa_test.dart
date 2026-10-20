import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/services/recompensas_provider.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas del cambio de puntos de una recompensa (SCRUM-380): validar la
/// cantidad primero y solo entonces guardarla, y que el valor nuevo se vea
/// en los catálogos.
void main() {
  final hidratacion = recompensaDePrueba(id: 'recompensa-hidratacion');
  final botella = recompensaDePrueba(
    id: 'recompensa-botella',
    nombre: 'Botella TRAZA',
    descripcion: 'Botella reutilizable de 750 ml.',
    puntos: 300,
  );

  late RecompensasRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = RecompensasRepositorioFalso(
      recompensas: [hidratacion, botella],
    );
    container = ProviderContainer(
      overrides: [recompensasRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoCambioPuntos> cambiar(Recompensa recompensa, String texto) =>
      container.read(cambioPuntosRecompensaProvider).cambiar(recompensa, texto);

  /// Los puntos que tiene guardados la recompensa con [id].
  int puntosGuardados(String id) =>
      repositorio.recompensas.firstWhere((r) => r.id == id).puntosRequeridos;

  group('cambio válido (criterio 1 de SCRUM-380)', () {
    test(
      'guarda los puntos nuevos y devuelve la recompensa actualizada',
      () async {
        final resultado = await cambiar(hidratacion, '200');

        expect(resultado, isA<PuntosCambiados>());
        final cambiada = (resultado as PuntosCambiados).recompensa;
        expect(cambiada.id, 'recompensa-hidratacion');
        expect(cambiada.puntosRequeridos, 200);
        expect(puntosGuardados('recompensa-hidratacion'), 200);
      },
    );

    test(
      'al repositorio llegan esa recompensa y los puntos como entero',
      () async {
        await cambiar(hidratacion, '200');

        expect(repositorio.recompensaPorCambiar?.id, 'recompensa-hidratacion');
        expect(repositorio.puntosRecibidos, 200);
      },
    );

    test('recorta los espacios de lo escrito', () async {
      await cambiar(hidratacion, ' 200 ');

      expect(repositorio.puntosRecibidos, 200);
    });

    test('los bordes, 1 y 1000000 puntos, se guardan', () async {
      expect(await cambiar(hidratacion, '1'), isA<PuntosCambiados>());
      expect(puntosGuardados('recompensa-hidratacion'), 1);

      expect(await cambiar(hidratacion, '1000000'), isA<PuntosCambiados>());
      expect(puntosGuardados('recompensa-hidratacion'), 1000000);
    });

    test(
      'solo cambia esa recompensa: las demás conservan sus puntos',
      () async {
        await cambiar(hidratacion, '200');

        expect(puntosGuardados('recompensa-botella'), 300);
      },
    );

    test('el catálogo del corredor y la gestión se vuelven a consultar y ya '
        'traen el valor nuevo', () async {
      // Las dos listas están abiertas y ya cargadas antes del cambio.
      container.listen(catalogoRecompensasProvider, (_, _) {});
      container.listen(gestionRecompensasProvider, (_, _) {});
      await container.read(catalogoRecompensasProvider.future);
      await container.read(gestionRecompensasProvider.future);
      final consultasCatalogo = repositorio.consultasCatalogo;
      final consultasTodas = repositorio.consultasTodas;

      await cambiar(hidratacion, '200');

      final catalogo = await container.read(catalogoRecompensasProvider.future);
      final gestion = await container.read(gestionRecompensasProvider.future);
      expect(repositorio.consultasCatalogo, greaterThan(consultasCatalogo));
      expect(repositorio.consultasTodas, greaterThan(consultasTodas));
      expect(
        catalogo
            .firstWhere((r) => r.id == 'recompensa-hidratacion')
            .puntosRequeridos,
        200,
      );
      expect(
        gestion
            .firstWhere((r) => r.id == 'recompensa-hidratacion')
            .puntosRequeridos,
        200,
      );
    });
  });

  group('cantidad inválida (criterio 2 de SCRUM-380)', () {
    for (final (texto, mensaje) in [
      ('0', 'Los puntos deben ser mayores que cero.'),
      ('-3', 'Los puntos deben ser mayores que cero.'),
      ('abc', 'Usa solo números enteros.'),
      ('2.5', 'Usa solo números enteros.'),
      ('0x10', 'Usa solo números enteros.'),
      ('', 'Indica cuántos puntos cuesta.'),
      ('   ', 'Indica cuántos puntos cuesta.'),
      ('1000001', 'Máximo 1000000 puntos.'),
    ]) {
      test('con "$texto" no llega a la base, conserva el valor anterior e '
          'indica que la cantidad no es válida', () async {
        final resultado = await cambiar(hidratacion, texto);

        expect(resultado, isA<PuntosInvalidos>());
        expect((resultado as PuntosInvalidos).mensaje, mensaje);
        // Lo importante: ni se intentó guardar.
        expect(repositorio.puntosRecibidos, isNull);
        expect(repositorio.recompensaPorCambiar, isNull);
        expect(puntosGuardados('recompensa-hidratacion'), 150);
      });
    }

    test('el mensaje es el mismo de la regla de los puntos', () async {
      final resultado = await cambiar(hidratacion, '0') as PuntosInvalidos;

      expect(resultado.mensaje, errorDePuntos('0'));
    });

    test('lo que ve el corredor sigue con el valor anterior', () async {
      container.listen(catalogoRecompensasProvider, (_, _) {});
      await container.read(catalogoRecompensasProvider.future);

      await cambiar(hidratacion, '0');

      final catalogo = await container.read(catalogoRecompensasProvider.future);
      expect(
        catalogo
            .firstWhere((r) => r.id == 'recompensa-hidratacion')
            .puntosRequeridos,
        150,
      );
    });
  });

  group('el guardado falla', () {
    test('sin sesión lo dice', () async {
      repositorio.error = const SesionRequeridaParaRecompensasException();

      final resultado = await cambiar(hidratacion, '200');

      expect(resultado, isA<PuntosNoGuardados>());
      expect(
        (resultado as PuntosNoGuardados).mensaje,
        CambioPuntosRecompensa.sinSesion,
      );
    });

    test(
      'una cuenta sin rol de administrador recibe un mensaje claro',
      () async {
        // Es lo que llega cuando la policy de update, que exige es_admin(),
        // no deja tocar la fila.
        repositorio.error = const SoloAdministradorException();

        final resultado =
            await cambiar(hidratacion, '200') as PuntosNoGuardados;

        expect(resultado.mensaje, CambioPuntosRecompensa.soloAdministrador);
      },
    );

    test('si la base rechaza la cantidad, dice que no es válida', () async {
      repositorio.error = const DatosDeRecompensaInvalidosException(
        'recompensas_puntos_validos',
      );

      final resultado = await cambiar(hidratacion, '200') as PuntosNoGuardados;

      expect(resultado.mensaje, CambioPuntosRecompensa.datosRechazados);
    });

    test('un fallo de red se traduce a un mensaje reintentable', () async {
      repositorio.error = Exception('sin conexión');

      final resultado = await cambiar(hidratacion, '200') as PuntosNoGuardados;

      expect(resultado.mensaje, CambioPuntosRecompensa.noSePudo);
    });

    test('si falla, la recompensa conserva el valor anterior', () async {
      repositorio.error = Exception('sin conexión');

      await cambiar(hidratacion, '200');

      expect(puntosGuardados('recompensa-hidratacion'), 150);
    });

    test('los mensajes son los acordados, sin texto crudo de la base', () {
      expect(
        CambioPuntosRecompensa.sinSesion,
        'Inicia sesión para cambiar los puntos.',
      );
      expect(
        CambioPuntosRecompensa.soloAdministrador,
        'Solo el administrador puede cambiar los puntos.',
      );
      expect(
        CambioPuntosRecompensa.noSePudo,
        'No se pudieron cambiar los puntos. Inténtalo de nuevo.',
      );
      expect(
        CambioPuntosRecompensa.datosRechazados,
        'La cantidad de puntos no es válida.',
      );
    });
  });
}
