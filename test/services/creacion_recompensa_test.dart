import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/services/recompensas_provider.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas de la creación de recompensas (SCRUM-374): validar primero y solo
/// entonces registrar, y que lo registrado se vea en los catálogos.
void main() {
  const completo = BorradorRecompensa(
    nombre: 'Vale de hidratación',
    descripcion: 'Una bebida isotónica en la tienda aliada.',
    puntos: '150',
  );

  late RecompensasRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = RecompensasRepositorioFalso(
      recompensas: [
        recompensaDePrueba(
          id: 'recompensa-botella',
          nombre: 'Botella TRAZA',
          puntos: 300,
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [recompensasRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoCreacionRecompensa> crear(BorradorRecompensa borrador) =>
      container.read(creacionRecompensaProvider).crear(borrador);

  group('creación exitosa (criterio 1 de SCRUM-374)', () {
    test('registra la recompensa y devuelve lo que guardó la base', () async {
      final resultado = await crear(completo);

      expect(resultado, isA<RecompensaCreada>());
      final creada = (resultado as RecompensaCreada).recompensa;
      expect(creada.id, isNotEmpty);
      expect(creada.nombre, 'Vale de hidratación');
      expect(creada.puntosRequeridos, 150);
      expect(creada.disponible, isTrue);
    });

    test(
      'al repositorio llegan los cuatro datos, sin espacios de más',
      () async {
        await crear(
          completo.copyWith(
            nombre: '  Vale de hidratación ',
            descripcion: ' Una bebida isotónica en la tienda aliada.\n',
          ),
        );

        expect(repositorio.recibida!.aSupabase(), {
          'nombre': 'Vale de hidratación',
          'descripcion': 'Una bebida isotónica en la tienda aliada.',
          'puntos_requeridos': 150,
          'disponible': true,
        });
      },
    );

    test('respeta la disponibilidad que eligió el administrador', () async {
      final resultado =
          await crear(completo.copyWith(disponible: false)) as RecompensaCreada;

      expect(repositorio.recibida!.disponible, isFalse);
      expect(resultado.recompensa.disponible, isFalse);
    });

    test('el catálogo del corredor y la gestión se vuelven a consultar y ya '
        'la traen (criterios 1 y 3 de SCRUM-374)', () async {
      // Las dos listas están abiertas y ya cargadas antes de crear.
      container.listen(catalogoRecompensasProvider, (_, _) {});
      container.listen(gestionRecompensasProvider, (_, _) {});
      await container.read(catalogoRecompensasProvider.future);
      await container.read(gestionRecompensasProvider.future);
      final consultasCatalogo = repositorio.consultasCatalogo;
      final consultasTodas = repositorio.consultasTodas;

      await crear(completo);

      final catalogo = await container.read(catalogoRecompensasProvider.future);
      final gestion = await container.read(gestionRecompensasProvider.future);
      expect(repositorio.consultasCatalogo, greaterThan(consultasCatalogo));
      expect(repositorio.consultasTodas, greaterThan(consultasTodas));
      expect(catalogo.map((r) => r.nombre), contains('Vale de hidratación'));
      expect(gestion.map((r) => r.nombre), contains('Vale de hidratación'));
    });
  });

  group('datos inválidos (criterio 2 de SCRUM-374)', () {
    test('con todo vacío no toca la base y señala los tres campos', () async {
      final resultado = await crear(const BorradorRecompensa());

      expect(resultado, isA<RecompensaConErrores>());
      expect((resultado as RecompensaConErrores).errores, {
        CampoRecompensa.nombre: 'Ponle un nombre a la recompensa.',
        CampoRecompensa.descripcion: 'Describe en qué consiste.',
        CampoRecompensa.puntos: 'Indica cuántos puntos cuesta.',
      });
      // Lo importante: ni se intentó guardar.
      expect(repositorio.recibida, isNull);
    });

    test(
      'con cero puntos no llega a la base y solo marca los puntos',
      () async {
        final resultado = await crear(completo.copyWith(puntos: '0'));

        expect((resultado as RecompensaConErrores).errores, {
          CampoRecompensa.puntos: 'Los puntos deben ser mayores que cero.',
        });
        expect(repositorio.recibida, isNull);
      },
    );

    test('con puntos negativos tampoco', () async {
      final resultado = await crear(completo.copyWith(puntos: '-5'));

      expect((resultado as RecompensaConErrores).errores.keys, {
        CampoRecompensa.puntos,
      });
      expect(repositorio.recibida, isNull);
    });
  });

  group('el guardado falla', () {
    test('sin sesión lo dice', () async {
      repositorio.error = const SesionRequeridaParaRecompensasException();

      final resultado = await crear(completo);

      expect(resultado, isA<RecompensaNoGuardada>());
      expect(
        (resultado as RecompensaNoGuardada).mensaje,
        CreacionRecompensa.sinSesion,
      );
    });

    test(
      'una cuenta sin rol de administrador recibe un mensaje claro',
      () async {
        // Es lo que responde Postgres cuando la policy de insert, que exige
        // es_admin(), rechaza la fila.
        repositorio.error = const SoloAdministradorException();

        final resultado = await crear(completo) as RecompensaNoGuardada;

        expect(resultado.mensaje, CreacionRecompensa.soloAdministrador);
      },
    );

    test(
      'si la base rechaza los datos, se avisa sin culpar a la red',
      () async {
        repositorio.error = const DatosDeRecompensaInvalidosException(
          'recompensas_puntos_positivos',
        );

        final resultado = await crear(completo) as RecompensaNoGuardada;

        expect(resultado.mensaje, CreacionRecompensa.datosRechazados);
      },
    );

    test('un fallo de red se traduce a un mensaje reintentable', () async {
      repositorio.error = Exception('sin conexión');

      final resultado = await crear(completo) as RecompensaNoGuardada;

      expect(resultado.mensaje, CreacionRecompensa.noSePudo);
    });

    test('los mensajes son los acordados, sin texto crudo de la base', () {
      expect(
        CreacionRecompensa.sinSesion,
        'Inicia sesión para crear recompensas.',
      );
      expect(
        CreacionRecompensa.soloAdministrador,
        'Solo el administrador puede crear recompensas.',
      );
      expect(
        CreacionRecompensa.noSePudo,
        'No se pudo crear la recompensa. Inténtalo de nuevo.',
      );
      expect(
        CreacionRecompensa.datosRechazados,
        'Revisa los datos de la recompensa: la base no los aceptó.',
      );
    });
  });
}
