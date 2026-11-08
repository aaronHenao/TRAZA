import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;
import 'package:traza/services/rutas_oficiales_service.dart';

/// Pruebas del repositorio real de rutas oficiales (rutas oficiales, etapa
/// 1).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST. Que la base reacomode las posiciones y
/// niegue los cambios a quien no es administrador lo prueba el script de
/// `0058_rutas_oficiales.sql`.
void main() {
  Map<String, Object?> filaRuta(String id, String nombre, {String? dif}) => {
    'id': id,
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'entrenamiento_id': 'entrenamiento-$id',
    'nombre': nombre,
    'descripcion': null,
    'distancia_km': 5.23,
    'estado': 'publicada',
    'motivo_rechazo': null,
    'fecha_creacion': '2026-10-17T14:00:00+00:00',
    'fecha_publicacion': '2026-10-18T09:00:00+00:00',
    'dificultad': dif,
  };

  group('la lista (criterio 2)', () {
    test('pide rutas_oficiales con su ruta embebida, ordenadas por '
        'posición', () async {
      final supabase = _SupabaseFalso(
        respuesta: [
          {'posicion': 1, 'ruta': filaRuta('ruta-a', 'Vuelta al estadio')},
          {
            'posicion': 2,
            'ruta': filaRuta('ruta-b', 'Cerro Nutibara', dif: 'dificil'),
          },
        ],
      );
      addTearDown(supabase.cerrar);

      final oficiales = await supabase.repositorio.oficiales();

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/rutas_oficiales');
      final consulta = peticion.url.queryParameters;
      expect(consulta['order'], startsWith('posicion.asc'));
      // La ruta viene anidada bajo `ruta`, que es lo que lee RutaOficial.
      expect(consulta['select'], contains('posicion'));
      expect(consulta['select'], contains('ruta:rutas('));
      // Lo que muestra cada fila (criterio 2), sin el trazado: son cientos
      // de coordenadas que la lista no dibuja.
      for (final columna in ['autor_nombre', 'distancia_km', 'dificultad']) {
        expect(consulta['select'], contains(columna));
      }
      expect(consulta['select'], isNot(contains('trazado')));

      expect(oficiales.map((o) => o.posicion), [1, 2]);
      expect(oficiales.map((o) => o.ruta.id), ['ruta-a', 'ruta-b']);
      expect(oficiales.last.ruta.nombre, 'Cerro Nutibara');
      expect(oficiales.last.ruta.dificultad, Dificultad.dificil);
      expect(oficiales.first.ruta.dificultad, isNull);
    });

    test('sin rutas oficiales devuelve una lista vacía', () async {
      final supabase = _SupabaseFalso(respuesta: const []);
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio.oficiales(), isEmpty);
    });
  });

  group('agregar (criterio 3)', () {
    test('se lo pide a agregar_ruta_oficial, solo con la ruta: la posición '
        'la decide la base', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.agregar('ruta-1');

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/agregar_ruta_oficial');
      expect(jsonDecode(peticion.body), {'p_ruta_id': 'ruta-1'});
    });

    for (final (codigo, causa, excepcion) in [
      ('42501', 'no es administrador', isA<SoloAdministradorException>()),
      ('22023', 'la ruta no está publicada', isA<RutaNoPublicadaException>()),
      ('TZ404', 'la ruta ya no existe', isA<RutaNoPublicadaException>()),
      ('TZ409', 'la ruta ya es oficial', isA<RutaYaOficialException>()),
    ]) {
      test('si la base dice que $causa ($codigo), lo dice con su '
          'excepción', () {
        final supabase = _SupabaseFalso(codigoPostgres: codigo);
        addTearDown(supabase.cerrar);

        expect(supabase.repositorio.agregar('ruta-1'), throwsA(excepcion));
      });
    }

    test('un error que no es de los conocidos no se disfraza', () {
      final supabase = _SupabaseFalso(codigoPostgres: '08006');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.agregar('ruta-1'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '08006'),
        ),
      );
    });
  });

  group('mover (criterio 4)', () {
    test('se lo pide a mover_ruta_oficial, con la ruta y la posición '
        'nueva como entero', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.mover('ruta-1', 2);

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/mover_ruta_oficial');
      final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
      expect(cuerpo, {'p_ruta_id': 'ruta-1', 'p_posicion': 2});
      expect(cuerpo['p_posicion'], isA<int>());
    });

    test('si la base dice que no es administrador (42501), lo dice con su '
        'excepción', () {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.mover('ruta-1', 2),
        throwsA(isA<SoloAdministradorException>()),
      );
    });

    test('si la ruta ya no es oficial (TZ404), lo dice con su excepción', () {
      final supabase = _SupabaseFalso(codigoPostgres: 'TZ404');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.mover('ruta-1', 2),
        throwsA(isA<RutaNoOficialException>()),
      );
    });

    test('un error que no es de permisos no se disfraza', () {
      final supabase = _SupabaseFalso(codigoPostgres: '08006');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.mover('ruta-1', 2),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '08006'),
        ),
      );
    });
  });

  group('quitar (criterio 5)', () {
    test('se lo pide a quitar_ruta_oficial, con la ruta: no borra la fila '
        'directo', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.quitar('ruta-1');

      expect(supabase.peticiones.map((p) => (p.method, p.url.path)), [
        ('POST', '/rest/v1/rpc/quitar_ruta_oficial'),
      ]);
      expect(jsonDecode(supabase.peticiones.single.body), {
        'p_ruta_id': 'ruta-1',
      });
    });

    test('si la base dice que no es administrador (42501), lo dice con su '
        'excepción', () {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.quitar('ruta-1'),
        throwsA(isA<SoloAdministradorException>()),
      );
    });

    test('si la ruta ya no es oficial (TZ404), lo dice con su excepción', () {
      final supabase = _SupabaseFalso(codigoPostgres: 'TZ404');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.quitar('ruta-1'),
        throwsA(isA<RutaNoOficialException>()),
      );
    });

    test('un error que no es de permisos no se disfraza', () {
      final supabase = _SupabaseFalso(codigoPostgres: '08006');
      addTearDown(supabase.cerrar);

      expect(
        supabase.repositorio.quitar('ruta-1'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '08006'),
        ),
      );
    });
  });
}

/// PostgREST de mentira: contesta [respuesta] tal cual, o un error con
/// [codigoPostgres].
class _SupabaseFalso {
  _SupabaseFalso({this.respuesta, this.codigoPostgres}) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final Object? respuesta;
  final String? codigoPostgres;
  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  RutasOficialesRepository get repositorio =>
      SupabaseRutasOficialesRepository(cliente: cliente);

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
