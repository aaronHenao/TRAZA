import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';

import '../utiles/foro_repository_falso.dart';

/// Lo que la app hace con la moderación del foro (SCRUM-322): ediciones en
/// revisión, rechazos sin ver y la decisión del administrador.
void main() {
  late ForoRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = ForoRepositorioFalso(
      publicaciones: [publicacionDePrueba(id: 'pub-1', autorId: 'usuario-1')],
    );
    container = ProviderContainer(
      overrides: [
        foroRepositoryProvider.overrideWithValue(repositorio),
        usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
      ],
    );
    addTearDown(container.dispose);
  });

  const cambios = BorradorPublicacion(
    titulo: 'Tenis para trail',
    contenido: 'Ahora busco para montaña.',
  );

  group('editar una publicación', () {
    test('la edición de un corredor queda en revisión y no cambia lo '
        'publicado', () async {
      final resultado = await container
          .read(edicionPublicacionProvider)
          .editar('pub-1', cambios);

      expect(resultado, isA<EdicionEnRevision>());
      expect(
        repositorio.publicaciones.single.titulo,
        '¿Qué tenis para asfalto?',
      );
      await container.read(misModeracionesProvider.future);
      expect(
        container.read(edicionAbiertaDePublicacionProvider('pub-1')),
        isNotNull,
      );
    });

    test('la del administrador se aplica de una vez', () async {
      repositorio.comoAdmin = true;

      final resultado = await container
          .read(edicionPublicacionProvider)
          .editar('pub-1', cambios);

      expect(resultado, isA<PublicacionEditada>());
      expect(repositorio.publicaciones.single.titulo, 'Tenis para trail');
    });

    test('con una edición esperando no deja otra', () async {
      await container.read(edicionPublicacionProvider).editar('pub-1', cambios);

      final otra = await container
          .read(edicionPublicacionProvider)
          .editar(
            'pub-1',
            const BorradorPublicacion(titulo: 'Otro', contenido: 'Otro'),
          );

      expect(
        (otra as EdicionNoGuardada).mensaje,
        EdicionPublicacion.yaEnRevision,
      );
    });

    test('la edición abierta de otro autor no le cuenta', () async {
      repositorio.moderacionesGuardadas.add(
        moderacionDePrueba(
          autorId: 'otro',
          accion: AccionModeracion.edicion,
          estado: EstadoModeracion.enRevision,
        ),
      );

      await container.read(misModeracionesProvider.future);

      expect(
        container.read(edicionAbiertaDePublicacionProvider('pub-1')),
        isNull,
      );
    });
  });

  test('la edición de un comentario queda en revisión', () async {
    final comentario = comentarioDePrueba(autorId: 'usuario-1');
    repositorio.comentariosDe['pub-1'] = [comentario];

    final resultado = await container
        .read(edicionComentarioProvider)
        .editar(comentario, const BorradorComentario('Mejor unos Novablast'));

    expect(resultado, isA<EdicionComentarioEnRevision>());
    await container.read(misModeracionesProvider.future);
    expect(container.read(comentariosConEdicionAbiertaProvider('pub-1')), {
      'com-1',
    });
  });

  test('cuenta solo los rechazos que no ha visto (criterio 5)', () async {
    repositorio.moderacionesGuardadas.addAll([
      moderacionDePrueba(id: 'a'),
      moderacionDePrueba(id: 'b', vistaPorAutor: true),
      moderacionDePrueba(id: 'c', estado: EstadoModeracion.pendiente),
    ]);

    await container.read(misModeracionesProvider.future);

    expect(container.read(rechazosSinVerProvider), 1);
    expect(container.read(misRechazadosProvider).value!.map((m) => m.id), [
      'a',
      'b',
    ]);
  });

  group('la decisión del administrador (SCRUM-337)', () {
    setUp(() {
      repositorio.moderacionesGuardadas.add(
        moderacionDePrueba(estado: EstadoModeracion.pendiente),
      );
    });

    test('rechazar sin motivo no llega a la base', () async {
      final m = repositorio.moderacionesGuardadas.single;

      final resultado = await container
          .read(decisionModeracionProvider)
          .decidir(m, aprobar: false, motivo: '   ');

      expect(resultado, isA<DecisionSinMotivo>());
      expect(repositorio.decisionRecibida, isNull);
    });

    test('rechazar con motivo lo deja rechazado, con el administrador como '
        'responsable', () async {
      final m = repositorio.moderacionesGuardadas.single;

      final resultado = await container
          .read(decisionModeracionProvider)
          .decidir(m, aprobar: false, motivo: ' Spam ');

      final decidida = (resultado as ModeracionDecidida).moderacion;
      expect(decidida.rechazada, isTrue);
      expect(decidida.responsable, ResponsableModeracion.admin);
      expect(repositorio.decisionRecibida, ('mod-1', false, 'Spam'));
    });

    test('aprobar no manda motivo', () async {
      final m = repositorio.moderacionesGuardadas.single;

      await container
          .read(decisionModeracionProvider)
          .decidir(m, aprobar: true, motivo: 'ignorado');

      expect(repositorio.decisionRecibida, ('mod-1', true, null));
    });

    test('si ya la resolvió la IA u otro administrador, lo dice', () async {
      final m = repositorio.moderacionesGuardadas.single;
      await container
          .read(decisionModeracionProvider)
          .decidir(m, aprobar: true);

      final otra = await container
          .read(decisionModeracionProvider)
          .decidir(m, aprobar: true);

      expect(otra, isA<DecisionYaResuelta>());
    });
  });

  group('cambios en vivo', () {
    test('una publicación que pasa a publicada sin editarse es nueva para el '
        'foro', () {
      final cambio = SupabaseCambiosForo.cambioDesdeFila(
        TablaForo.publicaciones,
        TipoCambioForo.editado,
        {'id': 'pub-1', 'autor_id': 'u1', 'estado': 'publicada'},
      )!;

      expect(cambio.esPublicacionNueva, isTrue);
    });

    test('una edición aprobada sigue siendo una edición', () {
      final cambio = SupabaseCambiosForo.cambioDesdeFila(
        TablaForo.publicaciones,
        TipoCambioForo.editado,
        {
          'id': 'pub-1',
          'estado': 'publicada',
          'fecha_edicion': '2026-10-16T16:00:00+00:00',
        },
      )!;

      expect(cambio.esPublicacionNueva, isFalse);
    });

    test('un rechazo trae su motivo y su autor', () {
      final cambio = SupabaseCambiosForo.cambioDesdeFila(
        TablaForo.moderaciones,
        TipoCambioForo.editado,
        {
          'id': 'mod-1',
          'publicacion_id': 'pub-1',
          'autor_id': 'u1',
          'estado': 'rechazada',
          'motivo': 'Spam',
        },
      )!;

      expect(cambio.esRechazo, isTrue);
      expect(cambio.motivo, 'Spam');
      expect(cambio.autorId, 'u1');
      expect(cambio.publicacionId, 'pub-1');
    });

    test('lo que entra a la cola no es un rechazo', () {
      final cambio = SupabaseCambiosForo.cambioDesdeFila(
        TablaForo.moderaciones,
        TipoCambioForo.nuevo,
        {'id': 'mod-1', 'estado': 'en_revision'},
      )!;

      expect(cambio.esRechazo, isFalse);
    });
  });
}
