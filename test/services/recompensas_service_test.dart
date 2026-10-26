import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

/// Pruebas del repositorio real de recompensas (SCRUM-374).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifican las consultas que de
/// verdad salen hacia Supabase.
void main() {
  final fila = <String, Object?>{
    'id': 'recompensa-1',
    'nombre': 'Vale de hidratación',
    'descripcion': 'Una bebida isotónica en la tienda aliada.',
    'puntos_requeridos': 150,
    'disponible': true,
    'fecha_creacion': '2026-10-19T14:00:00+00:00',
  };

  final nueva = const BorradorRecompensa(
    nombre: 'Vale de hidratación',
    descripcion: 'Una bebida isotónica en la tienda aliada.',
    puntos: '150',
  ).aNuevaRecompensa()!;

  group('crear (criterio 1 de SCRUM-374)', () {
    test('registra la recompensa mandando solo lo que escribió el '
        'administrador', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      final creada = await supabase.repositorio.crear(nueva);

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/recompensas');
      // Ni id ni fecha_creacion: los pone la base.
      expect(jsonDecode(peticion.body), {
        'nombre': 'Vale de hidratación',
        'descripcion': 'Una bebida isotónica en la tienda aliada.',
        'puntos_requeridos': 150,
        'disponible': true,
      });
      // Lo que vuelve es la fila que guardó la base, con su id.
      expect(creada.id, 'recompensa-1');
      expect(creada.puntosRequeridos, 150);
    });

    test(
      'una recompensa no disponible viaja con disponible en false',
      () async {
        final supabase = _SupabaseFalso(
          filas: [
            {...fila, 'disponible': false},
          ],
        );
        addTearDown(supabase.cerrar);

        final oculta = const BorradorRecompensa(
          nombre: 'Vale de hidratación',
          descripcion: 'Una bebida isotónica en la tienda aliada.',
          puntos: '150',
          disponible: false,
        ).aNuevaRecompensa()!;

        final creada = await supabase.repositorio.crear(oculta);

        expect(
          (jsonDecode(supabase.peticiones.single.body) as Map)['disponible'],
          isFalse,
        );
        expect(creada.disponible, isFalse);
      },
    );

    test('si la tabla rechaza los datos (23514) lo dice con su excepción', () {
      final supabase = _SupabaseFalso(codigoPostgres: '23514');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.crear(nueva),
        throwsA(isA<DatosDeRecompensaInvalidosException>()),
      );
    });

    test('si RLS lo niega (42501) es que la cuenta no es administradora', () {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.crear(nueva),
        throwsA(isA<SoloAdministradorException>()),
      );
    });
  });

  group('catálogo del corredor (criterio 3 de SCRUM-374)', () {
    test('pide solo las disponibles, de menos a más puntos', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      final catalogo = await supabase.repositorio.catalogo();

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/recompensas');
      final consulta = peticion.url.queryParameters;
      expect(consulta['disponible'], 'eq.true');
      expect(consulta['order'], startsWith('puntos_requeridos.asc'));
      // Con los puntos que cuesta cada una.
      expect(catalogo.single.nombre, 'Vale de hidratación');
      expect(catalogo.single.puntosRequeridos, 150);
    });
  });

  group('gestión del administrador', () {
    test('pide todas, disponibles o no, de la más reciente a la más '
        'antigua', () async {
      final supabase = _SupabaseFalso(
        filas: [
          fila,
          {...fila, 'id': 'recompensa-2', 'disponible': false},
        ],
      );
      addTearDown(supabase.cerrar);

      final todas = await supabase.repositorio.todas();

      final consulta = supabase.peticiones.single.url.queryParameters;
      expect(consulta.keys, isNot(contains('disponible')));
      expect(consulta['order'], startsWith('fecha_creacion.desc'));
      expect(todas.map((r) => r.disponible), [true, false]);
    });
  });

  group('cambiar los puntos (SCRUM-380)', () {
    final recompensa = Recompensa.desdeSupabase(fila);

    test('actualiza solo esa recompensa, en recompensas y por su id, y '
        'devuelve la fila guardada (criterio 1 de SCRUM-380)', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {...fila, 'puntos_requeridos': 200},
        ],
      );
      addTearDown(supabase.cerrar);

      final cambiada = await supabase.repositorio.cambiarPuntos(
        recompensa,
        200,
      );

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'PATCH');
      expect(peticion.url.path, '/rest/v1/recompensas');
      final consulta = peticion.url.queryParameters;
      expect(consulta['id'], 'eq.recompensa-1');
      // Pide de vuelta la fila, y una sola (`.single()`).
      expect(consulta.keys, contains('select'));
      expect(peticion.headers['Accept'], contains('vnd.pgrst.object+json'));
      // Lo que vuelve es lo que quedó en la base.
      expect(cambiada.id, 'recompensa-1');
      expect(cambiada.puntosRequeridos, 200);
    });

    test('manda únicamente puntos_requeridos y no toca ninguna otra tabla: '
        'los canjes ya hechos quedan como estaban (criterio 3 de '
        'SCRUM-380)', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {...fila, 'puntos_requeridos': 200},
        ],
      );
      addTearDown(supabase.cerrar);

      await supabase.repositorio.cambiarPuntos(recompensa, 200);

      // Una sola petición, a recompensas: nada hacia los canjes.
      expect(supabase.peticiones.map((p) => (p.method, p.url.path)), [
        ('PATCH', '/rest/v1/recompensas'),
      ]);
      // Ni nombre, ni descripción, ni disponibilidad: solo los puntos.
      expect(jsonDecode(supabase.peticiones.single.body), {
        'puntos_requeridos': 200,
      });
      // Y filtra por esa recompensa, no por otra cosa.
      expect(supabase.peticiones.single.url.queryParameters.keys.toSet(), {
        'id',
        'select',
      });
    });

    test('los puntos viajan como entero, no como texto', () async {
      final supabase = _SupabaseFalso(filas: [fila]);
      addTearDown(supabase.cerrar);

      await supabase.repositorio.cambiarPuntos(recompensa, 150);

      expect(
        (jsonDecode(supabase.peticiones.single.body)
            as Map)['puntos_requeridos'],
        isA<int>(),
      );
    });

    test('si la tabla rechaza la cantidad (23514) lo dice con su excepción '
        '(criterio 2 de SCRUM-380)', () {
      final supabase = _SupabaseFalso(codigoPostgres: '23514');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.cambiarPuntos(recompensa, 0),
        throwsA(isA<DatosDeRecompensaInvalidosException>()),
      );
    });

    for (final (codigo, causa) in [
      ('42501', 'la seguridad a nivel de fila lo negó'),
      ('PGRST116', 'la policy no dejó tocar la fila'),
    ]) {
      test('si $causa ($codigo), es que la cuenta no es administradora', () {
        final supabase = _SupabaseFalso(codigoPostgres: codigo);
        addTearDown(supabase.cerrar);

        expect(
          () => supabase.repositorio.cambiarPuntos(recompensa, 200),
          throwsA(isA<SoloAdministradorException>()),
        );
      });
    }

    test('un error que no es de permisos ni de datos no se disfraza', () {
      final supabase = _SupabaseFalso(codigoPostgres: '08006');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.cambiarPuntos(recompensa, 200),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('sin sesión', () {
    test('cambiar los puntos no sale a la red (SCRUM-380)', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.cambiarPuntos(Recompensa.desdeSupabase(fila), 200),
        throwsA(isA<SesionRequeridaParaRecompensasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test('crear no sale a la red', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nueva),
        throwsA(isA<SesionRequeridaParaRecompensasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test('el catálogo tampoco', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.catalogo(),
        throwsA(isA<SesionRequeridaParaRecompensasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test('ni la gestión', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.todas(),
        throwsA(isA<SesionRequeridaParaRecompensasException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });
}

/// Cliente de Supabase que no sale a la red.
class _SupabaseFalso {
  _SupabaseFalso({
    this.filas = const [],
    this.codigoPostgres,
    this.usuarioActual = 'admin-1',
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

  RecompensasRepository get repositorio => SupabaseRecompensasRepository(
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
