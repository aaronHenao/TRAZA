import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';

import '../utiles/foro_repository_falso.dart';

/// Retirar una publicación del foro (SCRUM-242): qué queda hecho y qué se le
/// responde al administrador en cada caso.
///
/// El doble se comporta como `retirar_publicacion_foro`: comprueba el
/// permiso, exige el motivo y, si retira, anota el asiento de la bitácora
/// ([ForoRepositorioFalso.retiros], criterio 3) y el aviso al autor
/// ([ForoRepositorioFalso.avisosDeRetiro], criterio 2).
void main() {
  late ForoRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = ForoRepositorioFalso(
      publicaciones: [
        publicacionDePrueba(id: 'pub-1', titulo: 'Gana dinero fácil'),
      ],
    )..comoAdmin = true;
    container = ProviderContainer(
      overrides: [
        foroRepositoryProvider.overrideWithValue(repositorio),
        usuarioActualProvider.overrideWithValue(
          () => ForoRepositorioFalso.usuario,
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoRetiro> retirar(String? motivo) =>
      container.read(retiroPublicacionProvider).retirar('pub-1', motivo);

  PublicacionForo laPublicacion() =>
      repositorio.publicaciones.firstWhere((p) => p.id == 'pub-1');

  test('la retira del foro con su motivo, sin borrarla (criterio 1)', () async {
    final resultado = await retirar('Lenguaje ofensivo');

    expect(resultado, isA<PublicacionRetirada>());
    final publicacion = laPublicacion();
    expect(publicacion.estado, EstadoPublicacion.eliminada);
    expect(publicacion.motivoModeracion, 'Lenguaje ofensivo');
    // Baja lógica: la fila sigue ahí para que la bitácora y los reportes
    // tengan a qué apuntar.
    expect(repositorio.publicaciones, hasLength(1));
  });

  test('deja el asiento con el motivo en la bitácora (criterio 3)', () async {
    await retirar('Spam');

    expect(repositorio.retiros, [('pub-1', 'Spam')]);
  });

  test('avisa al autor de la publicación con el motivo (criterio 2)', () async {
    await retirar('Spam');

    // El aviso va al autor, no a quien la retiró.
    expect(repositorio.avisosDeRetiro, [('autor-pub-1', 'Spam')]);
  });

  test('una vez retirada, deja de salir en el foro (criterio 1)', () async {
    expect(await repositorio.publicadas(), hasLength(1));

    await retirar('Spam');

    expect(await repositorio.publicadas(), isEmpty);
  });

  test('el motivo se guarda recortado', () async {
    await retirar('   Lenguaje ofensivo   ');

    expect(laPublicacion().motivoModeracion, 'Lenguaje ofensivo');
    expect(repositorio.retiros, [('pub-1', 'Lenguaje ofensivo')]);
  });

  group('sin motivo no se toca la base', () {
    test('en blanco', () async {
      final resultado = await retirar(null);

      expect(resultado, isA<RetiroSinMotivo>());
      expect(laPublicacion().estado, EstadoPublicacion.publicada);
      expect(repositorio.retiros, isEmpty);
      expect(repositorio.avisosDeRetiro, isEmpty);
    });

    test('solo espacios', () async {
      final resultado = await retirar('   ');

      expect(resultado, isA<RetiroSinMotivo>());
      expect(repositorio.retiros, isEmpty);
    });

    test('lo que se le dice es para qué sirve el motivo', () {
      expect(RetiroPublicacion.sinMotivo, contains('leerá el autor'));
    });
  });

  test(
    'si otro administrador se adelantó, lo dice y no asienta otra vez',
    () async {
      await retirar('Spam');
      repositorio.retiros.clear();
      repositorio.avisosDeRetiro.clear();

      final resultado = await retirar('Otra vez');

      expect(resultado, isA<PublicacionYaEstabaRetirada>());
      expect(repositorio.retiros, isEmpty);
      expect(repositorio.avisosDeRetiro, isEmpty);
    },
  );

  test('si quien lo intenta no es administrador, lo dice', () async {
    repositorio.comoAdmin = false;

    final resultado = await retirar('Spam');

    expect(resultado, isA<RetiroNoPermitido>());
    expect(laPublicacion().estado, EstadoPublicacion.publicada);
    expect(repositorio.retiros, isEmpty);
  });

  test('si la publicación ya no existe, lo dice', () async {
    final resultado = await container
        .read(retiroPublicacionProvider)
        .retirar('pub-que-no-esta', 'Spam');

    expect(resultado, isA<RetiroSinPublicacion>());
    expect(repositorio.retiros, isEmpty);
  });

  test('un motivo más largo de lo que admite la base no retira nada', () async {
    final resultado = await retirar('x' * (maxCaracteresMotivoRetiro + 1));

    // El diálogo lo limita antes; si llegara, se le dice lo mismo que si
    // faltara.
    expect(resultado, isA<RetiroSinMotivo>());
    expect(laPublicacion().estado, EstadoPublicacion.publicada);
    expect(repositorio.retiros, isEmpty);
  });

  test('un fallo de red avisa que no se pudo retirar', () async {
    repositorio.errorAlRetirar = Exception('sin red');

    final resultado = await retirar('Spam');

    expect(
      resultado,
      isA<RetiroNoGuardado>().having(
        (r) => r.mensaje,
        'mensaje',
        RetiroPublicacion.noSePudo,
      ),
    );
    expect(laPublicacion().estado, EstadoPublicacion.publicada);
  });

  test('sin sesión pide iniciarla', () async {
    repositorio.errorAlRetirar = const SesionRequeridaParaForoException();

    final resultado = await retirar('Spam');

    expect(
      resultado,
      isA<RetiroNoGuardado>().having(
        (r) => r.mensaje,
        'mensaje',
        RetiroPublicacion.sinSesion,
      ),
    );
  });

  test('las listas se vuelven a pedir después de retirar, y también cuando '
      'no se pudo', () async {
    // Quien mira la lista: sin un oyente, invalidar no vuelve a consultar.
    container.listen(moderacionForoProvider, (_, _) {});
    await container.read(moderacionForoProvider.future);
    final consultasIniciales = repositorio.consultas;

    await retirar('Spam');
    await container.read(moderacionForoProvider.future);
    expect(repositorio.consultas, greaterThan(consultasIniciales));

    // Si otro se adelantó, la lista en pantalla también está vieja.
    final tras = repositorio.consultas;
    await retirar('Otra vez');
    await container.read(moderacionForoProvider.future);
    expect(repositorio.consultas, greaterThan(tras));
  });
}
