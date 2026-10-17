import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/services/foro_service.dart';

/// Pruebas del repositorio real del foro (SCRUM-343).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifican las consultas que de
/// verdad salen hacia Supabase.
void main() {
  final fila = {
    'id': 'pub-1',
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'titulo': 'Tenis',
    'contenido': '¿Cuáles?',
    'estado': 'publicada',
    'motivo_moderacion': null,
    'fecha_creacion': '2026-10-16T14:00:00+00:00',
  };

  final nueva = const BorradorPublicacion(
    titulo: 'Tenis',
    contenido: '¿Cuáles?',
  ).aNuevaPublicacion()!;

  test('publica a nombre del usuario sin mandar nombre ni estado', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    final creada = await supabase.repositorio.crear(nueva);

    expect(creada.autorNombre, 'Ana');
    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/publicaciones_foro');
    expect(jsonDecode(peticion.body), {
      'titulo': 'Tenis',
      'contenido': '¿Cuáles?',
      'autor_id': 'usuario-1',
    });
  });

  test('el foro pide solo lo publicado, lo más reciente primero', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    final lista = await supabase.repositorio.publicadas();

    expect(lista.single.estado, EstadoPublicacion.publicada);
    final consulta = supabase.peticiones.single.url.queryParameters;
    expect(consulta['estado'], 'eq.publicada');
    expect(consulta['order'], startsWith('fecha_creacion.desc'));
  });

  test('la moderación no filtra por estado', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    await supabase.repositorio.todasParaModeracion();

    expect(
      supabase.peticiones.single.url.queryParameters.keys,
      isNot(contains('estado')),
    );
  });

  test('el foro trae cuántos comentarios tiene cada publicación', () async {
    final supabase = _SupabaseFalso(
      filas: [
        {
          ...fila,
          'comentarios_foro': [
            {'count': 3},
          ],
        },
      ],
    );
    addTearDown(supabase.cerrar);

    final lista = await supabase.repositorio.publicadas();

    expect(
      supabase.peticiones.single.url.queryParameters['select'],
      contains('comentarios_foro(count)'),
    );
    expect(lista.single.numeroComentarios, 3);
  });

  group('comentarios (SCRUM-350)', () {
    final filaComentario = {
      'id': 'com-1',
      'publicacion_id': 'pub-1',
      'autor_id': 'usuario-1',
      'autor_nombre': 'Ana',
      'contenido': 'Buen dato',
      'fecha_creacion': '2026-10-16T15:00:00+00:00',
    };
    final nuevo = const BorradorComentario(
      'Buen dato',
    ).aNuevoComentario('pub-1')!;

    test('comenta a nombre del usuario sin mandar su nombre', () async {
      final supabase = _SupabaseFalso(filas: [filaComentario]);
      addTearDown(supabase.cerrar);

      final comentario = await supabase.repositorio.comentar(nuevo);

      expect(comentario.autorNombre, 'Ana');
      final peticion = supabase.peticiones.single;
      expect(peticion.url.path, '/rest/v1/comentarios_foro');
      expect(jsonDecode(peticion.body), {
        'publicacion_id': 'pub-1',
        'contenido': 'Buen dato',
        'autor_id': 'usuario-1',
      });
    });

    test(
      'lee los comentarios de una publicación en orden de llegada',
      () async {
        final supabase = _SupabaseFalso(filas: [filaComentario]);
        addTearDown(supabase.cerrar);

        final lista = await supabase.repositorio.comentarios('pub-1');

        expect(lista.single.contenido, 'Buen dato');
        final consulta = supabase.peticiones.single.url.queryParameters;
        expect(consulta['publicacion_id'], 'eq.pub-1');
        expect(consulta['order'], startsWith('fecha_creacion.asc'));
      },
    );

    for (final (codigo, causa) in [
      ('42501', 'la publicación ya no está publicada'),
      ('23503', 'la publicación ya no existe'),
    ]) {
      test('si $causa ($codigo), la publicación no está disponible', () async {
        final supabase = _SupabaseFalso(codigoPostgres: codigo);
        addTearDown(supabase.cerrar);

        expect(
          () => supabase.repositorio.comentar(nuevo),
          throwsA(isA<PublicacionNoDisponibleException>()),
        );
      });
    }
  });

  test('si la tabla rechaza los datos lo dice con su excepción', () async {
    final supabase = _SupabaseFalso(codigoPostgres: '23514');
    addTearDown(supabase.cerrar);

    expect(
      () => supabase.repositorio.crear(nueva),
      throwsA(isA<DatosDePublicacionInvalidosException>()),
    );
  });

  test('sin sesión no sale ninguna petición', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    expect(
      () => supabase.repositorio.crear(nueva),
      throwsA(isA<SesionRequeridaParaForoException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });
}

/// Cliente de Supabase que no sale a la red.
class _SupabaseFalso {
  _SupabaseFalso({
    this.filas = const [],
    this.codigoPostgres,
    this.usuarioActual = 'usuario-1',
  }) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final List<Map<String, Object?>> filas;
  final String? codigoPostgres;
  final String? usuarioActual;
  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  ForoRepository get repositorio => SupabaseForoRepository(
    cliente: cliente,
    usuarioActual: () => usuarioActual,
  );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    const encabezados = {'content-type': 'application/json'};

    final codigo = codigoPostgres;
    if (codigo != null) {
      return http.Response(
        jsonEncode({'message': 'Error de prueba', 'code': codigo}),
        400,
        headers: encabezados,
        request: peticion,
      );
    }

    final unaSola = peticion.headers['Accept']?.contains(
      'vnd.pgrst.object+json',
    );
    final cuerpo = unaSola == true
        ? (filas.isEmpty ? null : filas.first)
        : filas;

    return http.Response(
      jsonEncode(cuerpo),
      200,
      headers: encabezados,
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
