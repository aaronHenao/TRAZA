import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/rutas_service.dart';

/// Pruebas del repositorio real de rutas (SCRUM-241).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifican las consultas que de
/// verdad salen hacia Supabase y qué hace con los errores que vuelven.
void main() {
  final fila = {
    'id': 'ruta-1',
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'entrenamiento_id': 'entrenamiento-1',
    'nombre': 'Vuelta al estadio',
    'descripcion': null,
    'trazado': [
      {'lat': 6.2442, 'lng': -75.5812},
      {'lat': 6.2450, 'lng': -75.5800},
    ],
    'distancia_km': 4.2,
    'estado': 'en_revision',
    'motivo_rechazo': null,
    'fecha_creacion': '2026-10-17T14:00:00+00:00',
    'fecha_publicacion': null,
  };

  final nueva = BorradorRuta(
    entrenamientoId: 'entrenamiento-1',
    nombre: 'Vuelta al estadio',
    puntos: [
      PuntoGps(
        latitud: 6.2442,
        longitud: -75.5812,
        capturadoEn: DateTime(2026, 10, 17, 7),
      ),
      PuntoGps(
        latitud: 6.2450,
        longitud: -75.5800,
        capturadoEn: DateTime(2026, 10, 17, 7, 1),
      ),
    ],
  ).aNuevaRuta()!;

  group('crear', () {
    test(
      'manda la ruta a nombre del usuario y nada de lo que pone la base',
      () async {
        final supabase = _SupabaseFalso(filas: [fila]);
        addTearDown(supabase.cerrar);

        final creada = await supabase.repositorio.crear(nueva);

        // La ruta nace en revisión: publicarla la manda a revisión, no la
        // publica (criterio 1).
        expect(creada.estado, EstadoRuta.enRevision);
        expect(creada.autorNombre, 'Ana');
        expect(creada.distanciaKm, 4.2);

        final peticion = supabase.peticiones.single;
        expect(peticion.method, 'POST');
        expect(peticion.url.path, '/rest/v1/rutas');
        expect(jsonDecode(peticion.body), {
          'entrenamiento_id': 'entrenamiento-1',
          'nombre': 'Vuelta al estadio',
          'autor_id': 'usuario-1',
          'trazado': [
            {'lat': 6.2442, 'lng': -75.5812},
            {'lat': 6.2450, 'lng': -75.5800},
          ],
        });
      },
    );

    test('sin sesion no sale ninguna peticion', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nueva),
        throwsA(isA<SesionRequeridaParaRutasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test('si la policy no deja, lo dice por el entrenamiento', () async {
      // 42501: la policy de insert exige que el entrenamiento sea del
      // usuario y esté finalizado.
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nueva),
        throwsA(isA<EntrenamientoNoPublicableException>()),
      );
    });

    test('un entrenamiento que ya no existe se trata igual', () async {
      // 23503: la clave foránea no encuentra a quién apuntar.
      final supabase = _SupabaseFalso(codigoPostgres: '23503');
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nueva),
        throwsA(isA<EntrenamientoNoPublicableException>()),
      );
    });

    test('el mismo entrenamiento dos veces no pasa dos veces', () async {
      // 23505: el índice único de 0031. Pasa por un doble toque o por
      // reintentar un envío que en realidad había funcionado.
      final supabase = _SupabaseFalso(codigoPostgres: '23505');
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nueva),
        throwsA(isA<EntrenamientoYaPublicadoException>()),
      );
    });

    test('una restriccion incumplida habla de los datos de la ruta', () async {
      // 23514: el nombre, el trazado o el trigger que lo revisa.
      final supabase = _SupabaseFalso(codigoPostgres: '23514');
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nueva),
        throwsA(isA<DatosDeRutaInvalidosException>()),
      );
    });
  });

  group('misRutas', () {
    test('pide solo las del autor, de la mas reciente, sin trazado', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      final rutas = await supabase.repositorio.misRutas();

      expect(rutas.single.id, 'ruta-1');

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.queryParameters['autor_id'], 'eq.usuario-1');
      expect(
        peticion.url.queryParameters['order'],
        startsWith('fecha_creacion.desc'),
      );
      // Un listado no dibuja trazados; pedirlos serían cientos de
      // coordenadas por fila para nada.
      expect(
        peticion.url.queryParameters['select'],
        isNot(contains('trazado')),
      );
    });
  });

  group('rutaDeEntrenamiento', () {
    test('busca la del autor y no cuenta las rechazadas', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      final ruta = await supabase.repositorio.rutaDeEntrenamiento(
        'entrenamiento-1',
      );

      expect(ruta?.id, 'ruta-1');

      final peticion = supabase.peticiones.single;
      expect(peticion.url.queryParameters['autor_id'], 'eq.usuario-1');
      expect(
        peticion.url.queryParameters['entrenamiento_id'],
        'eq.entrenamiento-1',
      );
      // Una rechazada se puede corregir y volver a mandar, así que no
      // cuenta como "ya la publicaste".
      expect(peticion.url.queryParameters['estado'], 'neq.rechazada');
    });
  });

  group('publicadas', () {
    test('pide solo las publicadas, de la ultima, sin trazado', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      final rutas = await supabase.repositorio.publicadas();

      expect(rutas.single.id, 'ruta-1');

      final peticion = supabase.peticiones.single;
      // El filtro va aunque RLS ya oculte lo ajeno en revision: al autor le
      // devolveria tambien lo suyo sin aprobar, y eso no es la comunidad.
      expect(peticion.url.queryParameters['estado'], 'eq.publicada');
      expect(
        peticion.url.queryParameters['order'],
        startsWith('fecha_publicacion.desc'),
      );
      expect(
        peticion.url.queryParameters['select'],
        isNot(contains('trazado')),
      );
    });
  });

  group('ruta', () {
    test('pide la ruta con su trazado', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      final ruta = await supabase.repositorio.ruta('ruta-1');

      expect(ruta?.trazado.length, 2);

      final peticion = supabase.peticiones.single;
      expect(peticion.url.queryParameters['id'], 'eq.ruta-1');
      expect(peticion.url.queryParameters['select'], contains('trazado'));
    });
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
