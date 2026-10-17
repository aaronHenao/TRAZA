import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';

import '../utiles/foro_repository_falso.dart';

/// Comentarios del foro: validación (SCRUM-352) y registro (SCRUM-350).
void main() {
  group('BorradorComentario', () {
    test('vacío o solo espacios no se puede enviar', () {
      expect(const BorradorComentario('').error, BorradorComentario.vacio);
      expect(const BorradorComentario('  \n ').error, BorradorComentario.vacio);
      expect(const BorradorComentario('').aNuevoComentario('p'), isNull);
    });

    test('acepta justo el límite y rechaza un carácter más', () {
      expect(BorradorComentario('a' * maxCaracteresComentario).error, isNull);
      expect(
        BorradorComentario('a' * (maxCaracteresComentario + 1)).error,
        BorradorComentario.muyLargo,
      );
    });

    test('se envía sin espacios de más y sin autor', () {
      final nuevo = const BorradorComentario(
        '  Buen dato  ',
      ).aNuevoComentario('pub-1')!;

      expect(nuevo.aSupabase(), {
        'publicacion_id': 'pub-1',
        'contenido': 'Buen dato',
      });
    });
  });

  group('ComentarioPublicacion', () {
    late ForoRepositorioFalso repositorio;
    late ProviderContainer container;

    setUp(() {
      repositorio = ForoRepositorioFalso(
        publicaciones: [publicacionDePrueba(id: 'pub-1')],
      );
      container = ProviderContainer(
        overrides: [foroRepositoryProvider.overrideWithValue(repositorio)],
      );
      addTearDown(container.dispose);
    });

    Future<ResultadoComentario> comentar(String texto) => container
        .read(comentarioForoProvider)
        .comentar('pub-1', BorradorComentario(texto));

    test('un comentario válido queda bajo la publicación', () async {
      final resultado = await comentar('Prueba con unos Pegasus.');

      expect(resultado, isA<ComentarioRegistrado>());
      final lista = await container.read(
        comentariosForoProvider('pub-1').future,
      );
      expect(lista.single.contenido, 'Prueba con unos Pegasus.');
      expect(lista.single.autorNombre, 'Ana Runner');
    });

    test('vacío no llega al repositorio y dice por qué', () async {
      final resultado = await comentar('   ');

      expect(
        (resultado as ComentarioInvalido).error,
        'El comentario no puede estar vacío.',
      );
      expect(repositorio.comentarioRecibido, isNull);
    });

    test('si la publicación dejó de estar disponible, lo informa y el '
        'detalle se entera', () async {
      expect(
        (await container.read(
          publicacionForoProvider('pub-1').future,
        ))!.admiteComentarios,
        isTrue,
      );
      repositorio
        ..retener('pub-1')
        ..errorAlComentar = const PublicacionNoDisponibleException();

      final resultado = await comentar('Llego tarde');

      expect(resultado, isA<PublicacionNoDisponible>());
      final ahora = await container.read(
        publicacionForoProvider('pub-1').future,
      );
      expect(ahora!.estado, EstadoPublicacion.retenida);
      expect(ahora.admiteComentarios, isFalse);
    });

    test('un fallo de red no se confunde con publicación retirada', () async {
      repositorio.errorAlComentar = Exception('sin red');

      final resultado = await comentar('Hola');

      expect(
        (resultado as ComentarioNoGuardado).mensaje,
        ComentarioPublicacion.noSePudo,
      );
    });
  });
}
