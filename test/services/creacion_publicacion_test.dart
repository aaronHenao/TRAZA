import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/borrador_publicacion.dart';
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

  test('si la base la deja retenida, se avisa como retenida', () async {
    repositorio.estadoAlCrear = EstadoPublicacion.retenida;

    final resultado = await publicar(valida);

    expect(resultado, isA<PublicacionRetenida>());
    final foro = await container.read(publicacionesForoProvider.future);
    expect(foro, isEmpty);
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

  test('la moderación filtra por estado en memoria', () async {
    repositorio.publicaciones.addAll([
      publicacionDePrueba(id: 'a'),
      publicacionDePrueba(id: 'b', estado: EstadoPublicacion.retenida),
    ]);

    container.read(vistaModeracionForoProvider.notifier).state =
        VistaModeracionForo.retenidas;
    await container.read(moderacionForoProvider.future);

    final retenidas = container.read(moderacionForoFiltradaProvider).value!;
    expect(retenidas.map((p) => p.id), ['b']);
  });
}
