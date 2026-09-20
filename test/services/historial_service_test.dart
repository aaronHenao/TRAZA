import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/historial_service.dart';
import 'package:traza/services/objetivos_service.dart';

/// Consulta del historial (SCRUM-124), con un cliente HTTP falso que
/// intercepta lo que se le manda a PostgREST.
void main() {
  const usuarioId = 'usuario-de-prueba';

  late List<http.Request> peticiones;
  late List<Map<String, Object?>> filas;
  late SupabaseClient cliente;

  setUp(() {
    peticiones = [];
    filas = [];
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((peticion) async {
        peticiones.add(peticion);
        return http.Response(
          jsonEncode(filas),
          200,
          headers: {'content-type': 'application/json'},
          request: peticion,
        );
      }),
    );
    addTearDown(cliente.dispose);
  });

  HistorialRepository repositorio(String? usuario) =>
      SupabaseHistorialRepository(
        cliente: cliente,
        usuarioActual: () => usuario,
      );

  test('pide solo los finalizados del usuario, del más reciente', () async {
    await repositorio(usuarioId).cargar();

    final peticion = peticiones.single;
    expect(peticion.method, 'GET');
    expect(peticion.url.path, '/rest/v1/entrenamientos');
    final parametros = peticion.url.queryParameters;
    expect(parametros['usuario_id'], 'eq.$usuarioId');
    expect(parametros['estado'], 'eq.finalizado');
    expect(parametros['order'], startsWith('fecha_fin.desc'));
    expect(parametros['limit'], '${SupabaseHistorialRepository.limite}');
    expect(parametros['select'], contains('tipos_actividad(nombre)'));
    expect(parametros['select'], isNot(contains('puntos_gps')));
  });

  test('convierte las filas en entrenamientos', () async {
    filas = [
      {
        'id': 'e2',
        'fecha_fin': '2026-09-14T12:00:00Z',
        'duracion_segundos': 1694,
        'distancia_total_m': 5100,
        'tipos_actividad': {'nombre': 'Correr'},
      },
      {
        'id': 'e1',
        'fecha_fin': '2026-09-10T12:00:00Z',
        'duracion_segundos': 1925,
        'distancia_total_m': '3200.5',
        'tipos_actividad': {'nombre': 'Caminar'},
      },
    ];

    final historial = await repositorio(usuarioId).cargar();

    expect(historial.map((e) => e.entrenamientoId), ['e2', 'e1']);
    expect(historial.first.nombreActividad, 'Correr');
    expect(historial.first.duracion, const Duration(seconds: 1694));
    expect(historial.last.distanciaMetros, 3200.5);
  });

  test('ignora filas incompletas', () async {
    filas = [
      {'id': 'sin-fecha', 'duracion_segundos': 60},
      {
        'id': 'e1',
        'fecha_fin': '2026-09-10T12:00:00Z',
        'duracion_segundos': 60,
      },
    ];

    final historial = await repositorio(usuarioId).cargar();

    expect(historial.map((e) => e.entrenamientoId), ['e1']);
  });

  test('sin sesión no consulta', () async {
    await expectLater(
      repositorio(null).cargar(),
      throwsA(isA<SesionRequeridaException>()),
    );
    expect(peticiones, isEmpty);
  });
}
