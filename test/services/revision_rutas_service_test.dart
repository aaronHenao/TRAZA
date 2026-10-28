import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/revision_rutas_service.dart';

/// Pruebas del repositorio real de la revisión de rutas (SCRUM-321).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifican las consultas y la
/// llamada a `decidir_revision_ruta` que de verdad salen hacia Supabase, y qué
/// hace con los errores que vuelven.
void main() {
  Map<String, Object?> fila({String estado = 'en_revision'}) => {
    'id': 'ruta-1',
    'autor_id': 'autor-1',
    'autor_nombre': 'Ana',
    'entrenamiento_id': 'entrenamiento-1',
    'nombre': 'Vuelta al estadio',
    'descripcion': 'Plana y con sombra',
    'trazado': [
      {'lat': 6.2442, 'lng': -75.5812},
      {'lat': 6.2450, 'lng': -75.5800},
    ],
    'distancia_km': 4.2,
    'estado': estado,
    'motivo_rechazo': null,
    'fecha_creacion': '2026-10-18T10:00:00Z',
    'fecha_publicacion': null,
  };

  group('pendientes', () {
    test('el administrador pide lo que espera su revision, lo mas antiguo '
        'primero y con trazado', () async {
      final supabase = _SupabaseFalso(respuesta: [fila()]);
      addTearDown(supabase.cerrar);

      final rutas = await supabase.repositorio.pendientes();

      final peticion = supabase.peticiones.single;
      expect(peticion.url.path, '/rest/v1/rutas');
      expect(peticion.url.queryParameters['estado'], 'eq.en_revision');
      expect(
        peticion.url.queryParameters['order'],
        startsWith('fecha_creacion.asc'),
      );
      expect(peticion.url.queryParameters['select'], contains('trazado'));
      expect(rutas.single.trazado.length, 2);
    });

    test('sin sesion no pregunta', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.pendientes(),
        throwsA(isA<SesionRequeridaParaRevisarException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });

  group('decidir', () {
    test('aprobar llama a la funcion de la base sin motivo', () async {
      final supabase = _SupabaseFalso(
        respuesta: fila(estado: 'revision_experto'),
      );
      addTearDown(supabase.cerrar);

      final ruta = await supabase.repositorio.decidir(
        'ruta-1',
        aprobar: true,
        motivo: 'esto no viaja',
      );

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/decidir_revision_ruta');
      expect(jsonDecode(peticion.body), {
        'p_ruta_id': 'ruta-1',
        'p_aprobar': true,
        'p_motivo': null,
      });
      expect(ruta.estado, EstadoRuta.revisionExperto);
    });

    test('rechazar manda el motivo', () async {
      final supabase = _SupabaseFalso(
        respuesta: {
          ...fila(estado: 'rechazada'),
          'motivo_rechazo': 'Cruza una autopista',
        },
      );
      addTearDown(supabase.cerrar);

      final ruta = await supabase.repositorio.decidir(
        'ruta-1',
        aprobar: false,
        motivo: 'Cruza una autopista',
      );

      expect(
        jsonDecode(supabase.peticiones.single.body)['p_motivo'],
        'Cruza una autopista',
      );
      expect(ruta.estado, EstadoRuta.rechazada);
      expect(ruta.motivoRechazo, 'Cruza una autopista');
    });

    test('tambien entiende la fila cuando llega en una lista', () async {
      final supabase = _SupabaseFalso(
        respuesta: [fila(estado: 'revision_experto')],
      );
      addTearDown(supabase.cerrar);

      final ruta = await supabase.repositorio.decidir('ruta-1', aprobar: true);

      expect(ruta.estado, EstadoRuta.revisionExperto);
    });

    test('sin el rol de la etapa, o siendo el autor, no se permite', () async {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.decidir('ruta-1', aprobar: true),
        throwsA(isA<RevisionNoPermitidaException>()),
      );
    });

    test(
      'el experto que intenta aprobar sin dificultad tampoco (0048)',
      () async {
        final supabase = _SupabaseFalso(codigoPostgres: '22023');
        addTearDown(supabase.cerrar);

        await expectLater(
          supabase.repositorio.decidir('ruta-1', aprobar: true),
          throwsA(isA<RevisionNoPermitidaException>()),
        );
      },
    );

    test('un rechazo sin motivo lo para la base (criterio 6)', () async {
      final supabase = _SupabaseFalso(codigoPostgres: '23514');
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.decidir('ruta-1', aprobar: false, motivo: ' '),
        throwsA(isA<MotivoDeRechazoInvalidoException>()),
      );
    });

    test('si otro revisor decidio primero lo dice', () async {
      for (final codigo in ['TZ409', 'TZ404']) {
        final supabase = _SupabaseFalso(codigoPostgres: codigo);
        addTearDown(supabase.cerrar);

        await expectLater(
          supabase.repositorio.decidir('ruta-1', aprobar: true),
          throwsA(isA<RutaYaRevisadaException>()),
          reason: codigo,
        );
      }
    });

    test('sin sesion no decide', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.decidir('ruta-1', aprobar: true),
        throwsA(isA<SesionRequeridaParaRevisarException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });
}

/// Cliente de Supabase que no sale a la red.
class _SupabaseFalso {
  _SupabaseFalso({
    this.respuesta = const <Object?>[],
    this.codigoPostgres,
    this.usuarioActual = 'revisor-1',
  }) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  /// Lo que contesta PostgREST: una lista de filas o una fila suelta.
  final Object? respuesta;
  final String? codigoPostgres;
  final String? usuarioActual;
  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  RevisionRutasRepository get repositorio => SupabaseRevisionRutasRepository(
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
      jsonEncode(respuesta),
      200,
      headers: encabezados,
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
