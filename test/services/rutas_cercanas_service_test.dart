import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/rutas_service.dart';

/// Pruebas de la consulta de rutas por cercanía del repositorio real
/// (SCRUM-246).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifica la llamada que de
/// verdad sale hacia `rutas_cercanas` (0037) y qué hace con lo que vuelve.
void main() {
  Map<String, Object?> fila(String id, double distanciaUsuario) => {
    'id': id,
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'entrenamiento_id': 'entrenamiento-$id',
    'nombre': 'Ruta $id',
    'descripcion': null,
    'distancia_km': 5.23,
    'estado': 'publicada',
    'motivo_rechazo': null,
    'fecha_creacion': '2026-10-17T14:00:00+00:00',
    'fecha_publicacion': '2026-10-18T09:00:00+00:00',
    'distancia_usuario_km': distanciaUsuario,
  };

  test('llama a rutas_cercanas con las coordenadas y el radio', () async {
    final supabase = _SupabaseFalso();
    addTearDown(supabase.cerrar);

    await supabase.repositorio.cercanas(
      latitud: 6.2442,
      longitud: -75.5812,
      radioKm: 50,
    );

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/rpc/rutas_cercanas');
    expect(jsonDecode(peticion.body), {
      'p_latitud': 6.2442,
      'p_longitud': -75.5812,
      'p_radio_km': 50,
      'p_limite': SupabaseRutasRepository.limite,
    });
  });

  test('devuelve las rutas en el orden de la base, con su distancia', () async {
    // La base ya las manda de la más cercana a la más lejana: el cliente no
    // las reordena.
    final supabase = _SupabaseFalso(
      filas: [fila('a', 1.2), fila('b', 3.4), fila('c', 9.8)],
    );
    addTearDown(supabase.cerrar);

    final cercanas = await supabase.repositorio.cercanas(
      latitud: 6.2442,
      longitud: -75.5812,
      radioKm: 50,
    );

    expect([for (final c in cercanas) c.ruta.id], ['a', 'b', 'c']);
    expect([for (final c in cercanas) c.distanciaKm], [1.2, 3.4, 9.8]);
  });

  test('sin rutas cerca devuelve una lista vacía, no un error', () async {
    final supabase = _SupabaseFalso();
    addTearDown(supabase.cerrar);

    final cercanas = await supabase.repositorio.cercanas(
      latitud: 6.2442,
      longitud: -75.5812,
      radioKm: 50,
    );

    expect(cercanas, isEmpty);
  });

  test('sin sesión no sale ninguna petición', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.cercanas(
        latitud: 6.2442,
        longitud: -75.5812,
        radioKm: 50,
      ),
      throwsA(isA<SesionRequeridaParaRutasException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  test('un error de la base llega a quien preguntó', () async {
    // Coordenadas fuera de rango: la función las rechaza con 22023. Desde la
    // app no deberían llegar, porque salen del GPS.
    final supabase = _SupabaseFalso(codigoPostgres: '22023');
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.cercanas(latitud: 200, longitud: 0, radioKm: 50),
      throwsA(isA<PostgrestException>()),
    );
  });
}

/// Un Supabase de mentira que responde lo que la prueba le indique y anota
/// lo que se le pidió.
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

  RutasRepository get repositorio => SupabaseRutasRepository(
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

    return http.Response(
      jsonEncode(filas),
      200,
      headers: encabezados,
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
