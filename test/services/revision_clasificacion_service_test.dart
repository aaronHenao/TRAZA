import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/services/rutas_service.dart';

/// Pruebas de la revisión de la clasificación en el repositorio real
/// (SCRUM-261 a SCRUM-264): la pregunta "¿puedo revisar?", confirmar,
/// corregir y cuándo se revisó.
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST. La regla en sí la prueban las
/// migraciones 0042 y 0054 contra un Postgres.
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

    test('cualquier otro error llega tal cual, como el de una base que '
        'todavía no tiene la 0054', () async {
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

  group('corregir la dificultad (SCRUM-263)', () {
    test('se lo pide a corregir_clasificacion, con la ruta y la nueva '
        'dificultad como la guarda la base', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.corregirClasificacion(
        'ruta-1',
        Dificultad.dificil,
      );

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/corregir_clasificacion');
      expect(jsonDecode(peticion.body), {
        'p_ruta_id': 'ruta-1',
        'p_dificultad': 'dificil',
      });
    });

    test('si la base no lo deja, es falta de permiso', () async {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.corregirClasificacion('ruta-1', Dificultad.facil),
        throwsA(isA<SinPermisoParaRevisarException>()),
      );
    });

    test('cualquier otro error llega tal cual', () async {
      final supabase = _SupabaseFalso(codigoPostgres: '22023');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.corregirClasificacion('ruta-1', Dificultad.facil),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '22023'),
        ),
      );
    });

    test('sin sesión no sale ninguna petición', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.corregirClasificacion('ruta-1', Dificultad.facil),
        throwsA(isA<SesionRequeridaParaRutasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });

  group('cuándo se revisó (SCRUM-264)', () {
    test('se lo pregunta a clasificacion_revisada_en, con la ruta, y lo da '
        'en la hora local', () async {
      final supabase = _SupabaseFalso(respuesta: '2026-10-20T15:30:00+00:00');
      addTearDown(supabase.cerrar);

      final fecha = await supabase.repositorio.clasificacionRevisadaEn(
        'ruta-1',
      );

      expect(fecha, DateTime.utc(2026, 10, 20, 15, 30).toLocal());
      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/clasificacion_revisada_en');
      expect(jsonDecode(peticion.body), {'p_ruta_id': 'ruta-1'});
    });

    test('si nadie la ha revisado, no hay fecha', () async {
      final supabase = _SupabaseFalso(respuesta: null);
      addTearDown(supabase.cerrar);

      expect(
        await supabase.repositorio.clasificacionRevisadaEn('ruta-1'),
        isNull,
      );
    });

    test('una respuesta que no es una fecha no se toma por una', () async {
      for (final respuesta in ['ayer', 42]) {
        final supabase = _SupabaseFalso(respuesta: respuesta);
        addTearDown(supabase.cerrar);

        await expectLater(
          supabase.repositorio.clasificacionRevisadaEn('ruta-1'),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('sin sesión no sale ninguna petición', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.clasificacionRevisadaEn('ruta-1'),
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
