import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/rutas_service.dart';

/// Pruebas de la búsqueda de rutas del repositorio real (SCRUM-254).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifica la llamada que de
/// verdad sale hacia `buscar_rutas` (0040) y qué hace con lo que vuelve.
void main() {
  Map<String, Object?> fila(String id, {double? distanciaUsuario}) => {
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
    'miniatura': [
      {'lat': 6.2566, 'lng': -75.5900},
      {'lat': 6.2580, 'lng': -75.5885},
    ],
  };

  test('llama a buscar_rutas con lo escrito y el límite', () async {
    final supabase = _SupabaseFalso();
    addTearDown(supabase.cerrar);

    await supabase.repositorio.buscar(termino: 'parque norte');

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/rpc/buscar_rutas');
    expect(jsonDecode(peticion.body), {
      'p_termino': 'parque norte',
      'p_limite': SupabaseRutasRepository.limite,
    });
  });

  test(
    'con la ubicación del usuario la manda, para ordenar por cercanía',
    () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.buscar(
        termino: 'parque',
        latitud: 6.2442,
        longitud: -75.5812,
      );

      final cuerpo = jsonDecode(supabase.peticiones.single.body) as Map;
      expect(cuerpo['p_latitud'], 6.2442);
      expect(cuerpo['p_longitud'], -75.5812);
    },
  );

  test('con una sola coordenada no manda ninguna: la base rechazaría la '
      'consulta', () async {
    final supabase = _SupabaseFalso();
    addTearDown(supabase.cerrar);

    await supabase.repositorio.buscar(termino: 'parque', latitud: 6.2442);

    final cuerpo = jsonDecode(supabase.peticiones.single.body) as Map;
    expect(cuerpo.containsKey('p_latitud'), isFalse);
    expect(cuerpo.containsKey('p_longitud'), isFalse);
  });

  test('devuelve las rutas en el orden de la base, con su miniatura', () async {
    // La base ya las manda ordenadas: el cliente no las reordena.
    final supabase = _SupabaseFalso(
      filas: [
        fila('c', distanciaUsuario: 0.8),
        fila('a', distanciaUsuario: 2.5),
        fila('b', distanciaUsuario: 7.1),
      ],
    );
    addTearDown(supabase.cerrar);

    final rutas = await supabase.repositorio.buscar(termino: 'ruta');

    expect([for (final ruta in rutas) ruta.id], ['c', 'a', 'b']);
    expect(rutas.first.miniatura, hasLength(2));
    // Un listado no trae el trazado.
    expect(rutas.first.trazado, isEmpty);
  });

  test(
    'sin la ubicación la distancia al usuario llega nula y se lee igual',
    () async {
      final supabase = _SupabaseFalso(filas: [fila('a')]);
      addTearDown(supabase.cerrar);

      final rutas = await supabase.repositorio.buscar(termino: 'ruta');

      expect(rutas.single.nombre, 'Ruta a');
    },
  );

  test('sin coincidencias devuelve una lista vacía, no un error', () async {
    final supabase = _SupabaseFalso();
    addTearDown(supabase.cerrar);

    expect(await supabase.repositorio.buscar(termino: 'zzz'), isEmpty);
  });

  test('sin sesión no sale ninguna petición', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.buscar(termino: 'parque'),
      throwsA(isA<SesionRequeridaParaRutasException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  test('un error de la base llega a quien preguntó', () async {
    // Una sola letra: la función la rechaza con 22023. Desde la app no
    // debería llegar, porque la pantalla no busca con menos de dos.
    final supabase = _SupabaseFalso(codigoPostgres: '22023');
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.buscar(termino: 'a'),
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
