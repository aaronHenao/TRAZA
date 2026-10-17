import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/experiencia_ganada.dart';
import 'package:traza/models/regla_experiencia.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;

/// Pruebas del repositorio real de experiencia (SCRUM-203).
///
/// No hay base de datos: un cliente HTTP falso intercepta la petición que el
/// repositorio le manda a PostgREST y responde lo que la prueba necesita.
void main() {
  group('ganadaEn', () {
    test('lee las filas del entrenamiento con el nombre del reto', () async {
      final supabase = _SupabaseFalso(
        respuesta: [
          {
            'origen': 'actividad',
            'cantidad': 30,
            'ajuste': 'ninguno',
            'retos_usuario': null,
          },
          {
            'origen': 'reto',
            'cantidad': 400,
            'ajuste': null,
            'retos_usuario': {
              'retos': {'nombre': 'Diez km'},
            },
          },
        ],
      );
      addTearDown(supabase.cerrar);

      final xp = await supabase.repositorio.ganadaEn('e-1');

      expect(
        xp,
        const ExperienciaDeEntrenamiento(
          xpActividad: 30,
          ajuste: AjusteExperiencia.ninguno,
          retos: [RetoCompletado(nombre: 'Diez km', xp: 400)],
        ),
      );

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/experiencia_ganada');
      expect(peticion.url.queryParameters['entrenamiento_id'], 'eq.e-1');
      expect(
        peticion.url.queryParameters['select'],
        contains('retos_usuario(retos(nombre))'),
      );
    });

    test('sin filas, el entrenamiento no se procesó', () async {
      final supabase = _SupabaseFalso(respuesta: const []);
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio.ganadaEn('e-1'), isNull);
    });

    test('sin sesión no consulta', () async {
      final supabase = _SupabaseFalso(respuesta: const [], usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.ganadaEn('e-1'),
        throwsA(isA<SesionRequeridaException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });

  group('experienciaAcumulada', () {
    test('llama a experiencia_total y devuelve la suma', () async {
      final supabase = _SupabaseFalso(respuesta: 560);
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio.experienciaAcumulada(), 560);

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/experiencia_total');
    });

    test('sin sesión no consulta', () async {
      final supabase = _SupabaseFalso(respuesta: 0, usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.experienciaAcumulada(),
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

  ExperienciaRepository get repositorio => SupabaseExperienciaRepository(
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
