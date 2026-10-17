import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/insignias_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;

/// Pruebas del repositorio real de insignias (SCRUM-193).
///
/// No hay base de datos: un cliente HTTP falso intercepta la petición que el
/// repositorio le manda a PostgREST y responde lo que la prueba necesita.
void main() {
  group('listar', () {
    test('pide todo el catálogo de menor a mayor XP, con lo que el usuario ya '
        'obtuvo', () async {
      final supabase = _SupabaseFalso(
        respuesta: const [
          {
            'id': 'i-1',
            'nombre': 'Primera huella',
            'descripcion': 'Tu primer kilómetro con TRAZA',
            'icono': 'huella',
            'xp_requerida': 5,
            'insignias_usuario': [
              {'fecha_obtencion': '2026-09-20T15:00:00+00:00'},
            ],
          },
          {
            'id': 'i-3',
            'nombre': 'Diez mil',
            'descripcion': 'Tus primeros 10 km en una salida',
            'icono': 'diez',
            'xp_requerida': 105,
            'insignias_usuario': [],
          },
        ],
      );
      addTearDown(supabase.cerrar);

      final insignias = await supabase.repositorio.listar();

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/insignias');
      expect(
        peticion.url.queryParameters['select'],
        contains('insignias_usuario(fecha_obtencion)'),
      );
      expect(peticion.url.queryParameters['select'], contains('xp_requerida'));
      // `order()` de supabase agrega `.nullslast`; lo que importa es la
      // columna y el sentido.
      expect(
        peticion.url.queryParameters['order'],
        startsWith('xp_requerida.asc'),
      );

      expect(insignias.map((insignia) => insignia.id), ['i-1', 'i-3']);
      expect(insignias.first.nombre, 'Primera huella');
      expect(insignias.first.obtenida, isTrue);
      expect(insignias.last.xpRequerida, 105);
      expect(insignias.last.obtenida, isFalse);
    });

    test('sin insignias en el catálogo devuelve una lista vacía', () async {
      final supabase = _SupabaseFalso(respuesta: const []);
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio.listar(), isEmpty);
    });

    test('sin sesión no consulta', () async {
      final supabase = _SupabaseFalso(respuesta: const [], usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.listar(),
        throwsA(isA<SesionRequeridaException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });
}

class _SupabaseFalso {
  _SupabaseFalso({required this.respuesta, this.usuarioActual = 'usuario-1'}) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  /// Lo que responde PostgREST, sea cual sea la petición.
  final Object respuesta;

  /// La cuenta con la sesión abierta, o null para probar el caso sin sesión.
  final String? usuarioActual;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  InsigniasRepository get repositorio => SupabaseInsigniasRepository(
    cliente: cliente,
    usuarioActual: () => usuarioActual,
  );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    // PostgREST lee `response.request` al procesar la respuesta, así que el
    // falso la devuelve atada a su petición, igual que la red real.
    return http.Response(
      jsonEncode(respuesta),
      200,
      headers: const {'content-type': 'application/json'},
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
