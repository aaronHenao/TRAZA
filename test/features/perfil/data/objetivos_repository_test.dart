import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/features/perfil/data/objetivos_repository.dart';
import 'package:traza/features/perfil/domain/tipo_objetivo.dart';

/// Pruebas del repositorio real de objetivos (SCRUM-128).
///
/// No hay base de datos: un cliente HTTP falso intercepta cada petición que el
/// repositorio le manda a PostgREST y responde lo que la prueba necesita. Así
/// se verifican la tabla, los filtros y el upsert que de verdad salen hacia
/// Supabase, algo que las pruebas de la pantalla no ven porque usan un
/// repositorio de mentira.
void main() {
  const usuarioId = 'usuario-de-prueba';

  group('cargar', () {
    test('lee los objetivos del usuario desde la tabla objetivos', () async {
      final supabase = _SupabaseFalso(
        respuestaGet: [
          {'tipo': 'distancia', 'valor_meta': 12.5},
          {'tipo': 'frecuencia', 'valor_meta': 3},
        ],
      );
      addTearDown(supabase.cerrar);

      final objetivos = await supabase.repositorio(usuarioId).cargar();

      expect(objetivos, {
        TipoObjetivo.distancia: 12.5,
        TipoObjetivo.frecuencia: 3,
      });

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/objetivos');
      expect(peticion.url.queryParameters['select'], 'tipo,valor_meta');
      expect(peticion.url.queryParameters['usuario_id'], 'eq.$usuarioId');
    });

    test('acepta valor_meta en texto, como puede llegar un numeric', () async {
      final supabase = _SupabaseFalso(
        respuestaGet: [
          {'tipo': 'distancia', 'valor_meta': '7.5'},
        ],
      );
      addTearDown(supabase.cerrar);

      final objetivos = await supabase.repositorio(usuarioId).cargar();

      expect(objetivos, {TipoObjetivo.distancia: 7.5});
    });

    test('ignora tipos que la app no conoce', () async {
      final supabase = _SupabaseFalso(
        respuestaGet: [
          {'tipo': 'distancia', 'valor_meta': 10},
          {'tipo': 'calorias', 'valor_meta': 500},
        ],
      );
      addTearDown(supabase.cerrar);

      final objetivos = await supabase.repositorio(usuarioId).cargar();

      expect(objetivos, {TipoObjetivo.distancia: 10});
    });

    test('sin objetivos guardados devuelve un mapa vacío', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio(usuarioId).cargar(), isEmpty);
    });
  });

  group('guardar', () {
    test('hace upsert sobre (usuario_id, tipo) con los objetivos marcados', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio(usuarioId).guardar({
        TipoObjetivo.distancia: 12.5,
        TipoObjetivo.frecuencia: 3,
      });

      // Con los dos marcados no hay nada que borrar: una sola petición.
      final upsert = supabase.peticiones.single;
      expect(upsert.method, 'POST');
      expect(upsert.url.path, '/rest/v1/objetivos');
      expect(upsert.url.queryParameters['on_conflict'], 'usuario_id,tipo');
      expect(upsert.headers['Prefer'], contains('resolution=merge-duplicates'));
      expect(jsonDecode(upsert.body), [
        {'usuario_id': usuarioId, 'tipo': 'distancia', 'valor_meta': 12.5},
        {'usuario_id': usuarioId, 'tipo': 'frecuencia', 'valor_meta': 3},
      ]);
    });

    test('borra los desmarcados, y lo hace después de escribir', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio(usuarioId).guardar({
        TipoObjetivo.distancia: 10,
      });

      // El orden es lo que evita perder datos: si el borrado fallara, el
      // upsert ya estaría hecho.
      expect(supabase.peticiones.map((p) => p.method), ['POST', 'DELETE']);

      final borrado = supabase.peticiones.last;
      expect(borrado.url.path, '/rest/v1/objetivos');
      expect(borrado.url.queryParameters['usuario_id'], 'eq.$usuarioId');
      expect(borrado.url.queryParameters['tipo'], 'eq.frecuencia');
    });

    test('sin objetivos marcados no escribe nada y borra los dos tipos', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio(usuarioId).guardar({});

      expect(supabase.peticiones.map((p) => p.method), ['DELETE', 'DELETE']);
      expect(
        supabase.peticiones.map((p) => p.url.queryParameters['tipo']),
        ['eq.distancia', 'eq.frecuencia'],
      );
    });
  });

  test('sin sesión falla sin mandar ninguna petición', () async {
    final supabase = _SupabaseFalso();
    addTearDown(supabase.cerrar);
    final repositorio = supabase.repositorio(null);

    await expectLater(
      repositorio.cargar(),
      throwsA(isA<SesionRequeridaException>()),
    );
    await expectLater(
      repositorio.guardar({TipoObjetivo.distancia: 10}),
      throwsA(isA<SesionRequeridaException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });
}

/// Un [SupabaseClient] de verdad, pero con la red reemplazada: registra cada
/// petición y responde como lo haría PostgREST.
class _SupabaseFalso {
  _SupabaseFalso({this.respuestaGet = const []}) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  /// Filas que devuelve cualquier lectura.
  final List<Map<String, Object?>> respuestaGet;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  ObjetivosRepository repositorio(String? usuarioId) =>
      SupabaseObjetivosRepository(
        cliente: cliente,
        usuarioActual: () => usuarioId,
      );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    // PostgREST lee `response.request` al procesar la respuesta, así que el
    // falso la devuelve atada a su petición, igual que la red real.
    return switch (peticion.method) {
      'GET' => http.Response(
        jsonEncode(respuestaGet),
        200,
        headers: {'content-type': 'application/json'},
        request: peticion,
      ),
      'POST' => http.Response('', 201, request: peticion),
      _ => http.Response('', 204, request: peticion),
    };
  }

  Future<void> cerrar() => cliente.dispose();
}
