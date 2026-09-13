import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/entrenamiento_service.dart';

/// Pruebas del repositorio real de entrenamientos (SCRUM-121).
///
/// Igual que en las de objetivos, no hay base de datos: un cliente HTTP falso
/// intercepta la petición que el repositorio le manda a PostgREST y responde lo
/// que la prueba necesita. Así se verifica la actualización que de verdad sale
/// hacia Supabase.
void main() {
  test('cierra el entrenamiento con fecha_fin, duración, distancia y estado '
      'finalizado', () async {
    final supabase = _SupabaseFalso(
      filasActualizadas: [
        {'id': 'e-123'},
      ],
    );
    addTearDown(supabase.cerrar);

    await supabase.repositorio.finalizar(
      entrenamientoId: 'e-123',
      fechaFin: DateTime.utc(2026, 1, 1, 13, 32, 17),
      duracion: const Duration(minutes: 32, seconds: 17, milliseconds: 800),
      distanciaMetros: 5230.5,
    );

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'PATCH');
    expect(peticion.url.path, '/rest/v1/entrenamientos');
    expect(peticion.url.queryParameters['id'], 'eq.e-123');
    // Pide de vuelta las filas actualizadas para comprobar que hubo una.
    expect(peticion.url.queryParameters['select'], 'id');
    expect(jsonDecode(peticion.body), {
      'fecha_fin': '2026-01-01T13:32:17.000Z',
      // Los segundos completos: el cronómetro muestra 00:32:17.
      'duracion_segundos': 1937,
      'distancia_total_m': 5230.5,
      'estado': 'finalizado',
    });
  });

  test('sin distancia calculada deja distancia_total_m vacía', () async {
    final supabase = _SupabaseFalso(
      filasActualizadas: [
        {'id': 'e-123'},
      ],
    );
    addTearDown(supabase.cerrar);

    await supabase.repositorio.finalizar(
      entrenamientoId: 'e-123',
      fechaFin: DateTime.utc(2026, 1, 1, 13),
      duracion: const Duration(minutes: 5),
    );

    final cuerpo = jsonDecode(supabase.peticiones.single.body) as Map;
    expect(cuerpo.containsKey('distancia_total_m'), isTrue);
    expect(cuerpo['distancia_total_m'], isNull);
  });

  test('si no actualizó ninguna fila lo reporta como error', () async {
    // Id inexistente o fila de otro usuario: PostgREST responde bien, pero
    // vacío.
    final supabase = _SupabaseFalso(filasActualizadas: []);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.finalizar(
        entrenamientoId: 'e-otro',
        fechaFin: DateTime.utc(2026, 1, 1, 13),
        duracion: const Duration(minutes: 5),
      ),
      throwsA(
        isA<EntrenamientoNoEncontradoException>().having(
          (error) => error.entrenamientoId,
          'entrenamientoId',
          'e-otro',
        ),
      ),
    );
  });
}

/// Cliente de Supabase que no sale a la red: anota cada petición y responde
/// [filasActualizadas] como resultado de la actualización.
class _SupabaseFalso {
  _SupabaseFalso({required this.filasActualizadas}) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final List<Map<String, Object?>> filasActualizadas;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  EntrenamientoRepository get repositorio =>
      SupabaseEntrenamientoRepository(cliente: cliente);

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    // PostgREST lee `response.request` al procesar la respuesta, así que el
    // falso la devuelve atada a su petición, igual que la red real.
    return http.Response(
      jsonEncode(filasActualizadas),
      200,
      headers: {'content-type': 'application/json'},
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
