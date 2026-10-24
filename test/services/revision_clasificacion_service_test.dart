import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/rutas_service.dart';

/// Pruebas de la pregunta "¿puedo revisar la clasificación de esta ruta?"
/// del repositorio real (SCRUM-261).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST. La regla en sí la prueba la migración
/// 0042 contra un Postgres.
void main() {
  test('se lo pregunta a puede_revisar_clasificacion, con la ruta', () async {
    final supabase = _SupabaseFalso(respuesta: true);
    addTearDown(supabase.cerrar);

    final puede = await supabase.repositorio.puedeRevisarClasificacion(
      'ruta-1',
    );

    expect(puede, isTrue);
    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/rpc/puede_revisar_clasificacion');
    expect(jsonDecode(peticion.body), {'p_ruta_id': 'ruta-1'});
  });

  test('si la base dice que no, es que no', () async {
    final supabase = _SupabaseFalso(respuesta: false);
    addTearDown(supabase.cerrar);

    expect(
      await supabase.repositorio.puedeRevisarClasificacion('ruta-1'),
      isFalse,
    );
  });

  test('si contesta algo que no es sí o no, no lo toma por un sí', () async {
    final supabase = _SupabaseFalso(respuesta: null);
    addTearDown(supabase.cerrar);

    expect(
      supabase.repositorio.puedeRevisarClasificacion('ruta-1'),
      throwsA(isA<FormatException>()),
    );
  });

  test('si la base falla, el error llega a quien preguntó', () async {
    final supabase = _SupabaseFalso(codigoPostgres: '42501');
    addTearDown(supabase.cerrar);

    expect(
      supabase.repositorio.puedeRevisarClasificacion('ruta-1'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('sin sesión no sale ninguna petición', () async {
    final supabase = _SupabaseFalso(respuesta: true, usuarioActual: null);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.puedeRevisarClasificacion('ruta-1'),
      throwsA(isA<SesionRequeridaParaRutasException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  group('confirmar la dificultad propuesta (SCRUM-262)', () {
    test('se lo pide a confirmar_clasificacion, con la ruta', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.confirmarClasificacion('ruta-1');

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/confirmar_clasificacion');
      expect(jsonDecode(peticion.body), {'p_ruta_id': 'ruta-1'});
    });

    test('si la base no lo deja, es falta de permiso', () async {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.confirmarClasificacion('ruta-1'),
        throwsA(isA<SinPermisoParaRevisarException>()),
      );
    });

    test('cualquier otro error llega tal cual, como el de hoy, que la '
        'función todavía no existe', () async {
      // PostgREST contesta PGRST202 cuando no encuentra la función.
      final supabase = _SupabaseFalso(codigoPostgres: 'PGRST202');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.confirmarClasificacion('ruta-1'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PGRST202'),
        ),
      );
    });

    test('sin sesión no sale ninguna petición', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.confirmarClasificacion('ruta-1'),
        throwsA(isA<SesionRequeridaParaRutasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });
}

/// PostgREST de mentira: contesta [respuesta] tal cual, o un error con
/// [codigoPostgres].
class _SupabaseFalso {
  _SupabaseFalso({
    this.respuesta,
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

  final Object? respuesta;
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
      jsonEncode(respuesta),
      200,
      headers: encabezados,
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
