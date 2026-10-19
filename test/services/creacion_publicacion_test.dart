import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';

import '../utiles/foro_repository_falso.dart';

/// Creación de publicaciones en el foro (SCRUM-343).
void main() {
  late ForoRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = ForoRepositorioFalso();
    container = ProviderContainer(
      overrides: [foroRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoPublicacion> publicar(BorradorPublicacion borrador) =>
      container.read(creacionPublicacionProvider).publicar(borrador);

  const valida = BorradorPublicacion(
    titulo: 'Tenis para asfalto',
    contenido: '¿Qué me recomiendan?',
  );

  test('una publicación válida queda registrada y se ve en el foro', () async {
    final resultado = await publicar(valida);

    expect(resultado, isA<PublicacionCreada>());
    expect(repositorio.recibida?.titulo, 'Tenis para asfalto');
    final foro = await container.read(publicacionesForoProvider.future);
    expect(foro.single.titulo, 'Tenis para asfalto');
    expect(foro.single.autorNombre, 'Ana Runner');
  });

  test('una publicación inválida no llega al repositorio', () async {
    final resultado = await publicar(
      const BorradorPublicacion(titulo: '', contenido: '   '),
    );

    expect(resultado, isA<PublicacionConErrores>());
    expect(
      (resultado as PublicacionConErrores).errores.keys,
      containsAll([CampoPublicacion.titulo, CampoPublicacion.contenido]),
    );
    expect(repositorio.recibida, isNull);
  });

  test('si la base la deja en revisión, se avisa como en revisión', () async {
    repositorio.estadoAlCrear = EstadoPublicacion.enRevision;

    final resultado = await publicar(valida);

    expect(resultado, isA<PublicacionEnRevision>());
    // Su autor la ve en el foro, marcada (SCRUM-322).
    final foro = await container.read(publicacionesForoProvider.future);
    expect(foro.single.estado, EstadoPublicacion.enRevision);
  });

  test('sin sesión no se publica y se pide iniciarla', () async {
    repositorio.error = const SesionRequeridaParaForoException();

    final resultado = await publicar(valida);

    expect(
      (resultado as PublicacionNoGuardada).mensaje,
      CreacionPublicacion.sinSesion,
    );
  });

  test('un fallo de red no pierde lo escrito y se puede reintentar', () async {
    repositorio.error = Exception('sin red');

    final resultado = await publicar(valida);

    expect(
      (resultado as PublicacionNoGuardada).mensaje,
      CreacionPublicacion.noSePudo,
    );
  });

  test('la pestaña de publicadas solo muestra lo publicado', () async {
    repositorio.publicaciones.addAll([
      publicacionDePrueba(id: 'a'),
      publicacionDePrueba(id: 'b', estado: EstadoPublicacion.rechazada),
    ]);

    await container.read(moderacionForoProvider.future);

    final publicadas = container.read(moderacionForoFiltradaProvider).value!;
    expect(publicadas.map((p) => p.id), ['a']);
  });

  test('la moderación filtra por estado en memoria (SCRUM-337)', () async {
    repositorio.moderacionesGuardadas.addAll([
      moderacionDePrueba(id: 'm1', estado: EstadoModeracion.pendiente),
      moderacionDePrueba(id: 'm2'),
    ]);

    container.read(vistaModeracionForoProvider.notifier).state =
        VistaModeracionForo.pendientes;
    await container.read(moderacionesAdminProvider.future);

    final pendientes = container.read(moderacionesDeLaVistaProvider).value!;
    expect(pendientes.map((m) => m.id), ['m1']);
  });
}
