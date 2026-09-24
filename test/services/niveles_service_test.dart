import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/nuevo_nivel.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

/// Pruebas del repositorio real de niveles (SCRUM-180).
///
/// No hay base de datos: un cliente HTTP falso intercepta la petición que el
/// repositorio le manda a PostgREST y responde lo que la prueba necesita. Así
/// se verifican las consultas que de verdad salen hacia Supabase.
void main() {
  const nuevo = NuevoNivel(nombre: 'Bronce', umbralExperiencia: 100);

  group('crear', () {
    test('registra el nivel con la cuenta que tiene la sesión y devuelve la '
        'fila que creó la base', () async {
      final supabase = _SupabaseFalso(
        filaCreada: const {
          'id': 'n-1',
          'nombre': 'Bronce',
          'umbral_experiencia': 100,
        },
      );
      addTearDown(supabase.cerrar);

      final nivel = await supabase.repositorio.crear(nuevo);

      expect(nivel.id, 'n-1');
      expect(nivel.nombre, 'Bronce');
      expect(nivel.umbralExperiencia, 100);

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/niveles');
      expect(jsonDecode(peticion.body), {
        'nombre': 'Bronce',
        'umbral_experiencia': 100,
        'creado_por': 'usuario-1',
      });
    });

    test('sin sesión no intenta registrar nada', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nuevo),
        throwsA(isA<SesionRequeridaException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test('si la cuenta no es administradora, lo dice', () async {
      // Es la barrera de verdad: la policy de insert exige es_admin(), y
      // Postgres responde que la fila viola la seguridad a nivel de fila.
      final supabase = _SupabaseFalso(
        codigoError: 403,
        errorDePostgres: '42501',
        mensajeError: 'new row violates row-level security policy',
      );
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nuevo),
        throwsA(isA<SoloAdministradorException>()),
      );
    });

    test('distingue el nombre repetido del umbral repetido', () async {
      final porNombre = _SupabaseFalso(
        codigoError: 409,
        errorDePostgres: '23505',
        mensajeError:
            'duplicate key value violates unique constraint '
            '"niveles_nombre_unico_idx"',
      );
      addTearDown(porNombre.cerrar);

      await expectLater(
        porNombre.repositorio.crear(nuevo),
        throwsA(
          isA<NivelDuplicadoException>().having(
            (e) => e.esElNombre,
            'esElNombre',
            isTrue,
          ),
        ),
      );

      // El umbral repetido es el solapamiento del criterio 3 de SCRUM-177.
      final porUmbral = _SupabaseFalso(
        codigoError: 409,
        errorDePostgres: '23505',
        mensajeError:
            'duplicate key value violates unique constraint '
            '"niveles_umbral_unico"',
      );
      addTearDown(porUmbral.cerrar);

      await expectLater(
        porUmbral.repositorio.crear(nuevo),
        throwsA(
          isA<NivelDuplicadoException>().having(
            (e) => e.esElNombre,
            'esElNombre',
            isFalse,
          ),
        ),
      );
    });

    test('si la base rechaza los datos, el error lo dice', () async {
      final supabase = _SupabaseFalso(
        codigoError: 400,
        errorDePostgres: '23514',
        mensajeError:
            'new row for relation "niveles" violates check constraint '
            '"niveles_umbral_positivo"',
      );
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.crear(nuevo),
        throwsA(
          isA<DatosDeNivelInvalidosException>().having(
            (e) => e.detalle,
            'detalle',
            contains('niveles_umbral_positivo'),
          ),
        ),
      );
    });
  });

  group('listar', () {
    test('pide los niveles del umbral más bajo al más alto', () async {
      final supabase = _SupabaseFalso(
        filasLeidas: const [
          {'id': 'n-1', 'nombre': 'Bronce', 'umbral_experiencia': 100},
          {'id': 'n-2', 'nombre': 'Plata', 'umbral_experiencia': 500},
        ],
      );
      addTearDown(supabase.cerrar);

      final niveles = await supabase.repositorio.listar();

      expect(niveles.map((nivel) => nivel.nombre), ['Bronce', 'Plata']);

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/niveles');
      expect(
        peticion.url.queryParameters['order'],
        'umbral_experiencia.asc.nullslast',
      );
      expect(
        peticion.url.queryParameters['limit'],
        '${SupabaseNivelesRepository.limite}',
      );
    });

    test('sin niveles registrados devuelve una lista vacía', () async {
      final supabase = _SupabaseFalso(filasLeidas: const []);
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio.listar(), isEmpty);
    });

    test('sin sesión no consulta nada', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.listar(),
        throwsA(isA<SesionRequeridaException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });
  });
}

/// Cliente de Supabase que no sale a la red: anota cada petición y responde lo
/// que la prueba indique.
class _SupabaseFalso {
  _SupabaseFalso({
    this.filaCreada = const {},
    this.filasLeidas = const [],
    this.codigoError,
    this.errorDePostgres,
    this.mensajeError = '',
    this.usuarioActual = 'usuario-1',
  }) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  /// La fila que devuelve un insert, como hace `.select().single()`.
  final Map<String, Object?> filaCreada;

  /// Las filas que devuelve una lectura.
  final List<Map<String, Object?>> filasLeidas;

  /// Código HTTP del error, si la prueba quiere que falle.
  final int? codigoError;

  /// Código de error de Postgres que acompaña al fallo.
  final String? errorDePostgres;
  final String mensajeError;

  /// La cuenta con la sesión abierta, o null para probar el caso sin sesión.
  final String? usuarioActual;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  NivelesRepository get repositorio => SupabaseNivelesRepository(
    cliente: cliente,
    usuarioActual: () => usuarioActual,
  );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    const encabezados = {'content-type': 'application/json'};

    // PostgREST lee `response.request` al procesar la respuesta, así que el
    // falso la devuelve atada a su petición, igual que la red real.
    final codigoError = this.codigoError;
    if (codigoError != null) {
      return http.Response(
        jsonEncode({'message': mensajeError, 'code': errorDePostgres}),
        codigoError,
        headers: encabezados,
        request: peticion,
      );
    }

    return http.Response(
      jsonEncode(peticion.method == 'GET' ? filasLeidas : filaCreada),
      peticion.method == 'GET' ? 200 : 201,
      headers: encabezados,
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
