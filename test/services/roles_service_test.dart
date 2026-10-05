import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/rol_ganado.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;
import 'package:traza/services/roles_service.dart';

import '../utiles/roles_falso.dart';

/// Pruebas del repositorio real de roles ganados (SCRUM-228).
///
/// No hay base de datos: un cliente HTTP falso intercepta la petición que el
/// repositorio le manda a PostgREST y responde lo que la prueba necesita. Así
/// se verifica la consulta que de verdad sale hacia Supabase.
void main() {
  test('pide los roles del usuario, del más antiguo al más reciente', () async {
    final supabase = _SupabaseFalso(
      filasLeidas: const [
        {
          'rol': 'experto',
          'otorgado_en': '2026-10-02T15:00:00+00:00',
          'anunciado_en': null,
        },
      ],
    );
    addTearDown(supabase.cerrar);

    final roles = await supabase.repositorio.misRoles();

    expect(roles.single.rol, RolGanable.experto);
    expect(roles.single.anunciado, isFalse);

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'GET');
    expect(peticion.url.path, '/rest/v1/roles_usuario');
    expect(peticion.url.queryParameters['order'], 'otorgado_en.asc.nullslast');
    expect(
      peticion.url.queryParameters['limit'],
      '${SupabaseRolesRepository.limite}',
    );
  });

  test('una cuenta sin roles devuelve una lista vacía', () async {
    final supabase = _SupabaseFalso(filasLeidas: const []);
    addTearDown(supabase.cerrar);

    expect(await supabase.repositorio.misRoles(), isEmpty);
  });

  test('sin sesión no consulta nada', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.misRoles(),
      throwsA(isA<SesionRequeridaException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  test(
    'un rol que esta versión no conoce se ignora, no rompe la lista',
    () async {
      // Los roles los añade una migración: una app vieja puede encontrarse con
      // uno nuevo y tiene que poder seguir leyendo los demás.
      final supabase = _SupabaseFalso(
        filasLeidas: const [
          {
            'rol': 'maratonista',
            'otorgado_en': '2026-10-02T15:00:00+00:00',
            'anunciado_en': null,
          },
          {
            'rol': 'experto',
            'otorgado_en': '2026-10-03T15:00:00+00:00',
            'anunciado_en': null,
          },
        ],
      );
      addTearDown(supabase.cerrar);

      final roles = await supabase.repositorio.misRoles();

      expect(roles.map((ganado) => ganado.rol), [RolGanable.experto]);
    },
  );

  group('esExpertoProvider', () {
    ProviderContainer contenedor(RolesFalso repositorio) {
      final container = ProviderContainer(
        overrides: [rolesRepositoryProvider.overrideWithValue(repositorio)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('con el rol desbloqueado responde que sí', () async {
      final container = contenedor(RolesFalso.experto());

      expect(await container.read(esExpertoProvider.future), isTrue);
    });

    test('sin roles responde que no', () async {
      final container = contenedor(RolesFalso());

      expect(await container.read(esExpertoProvider.future), isFalse);
    });

    test(
      'el error de lectura llega tal cual, sin convertirse en un no',
      () async {
        // Quien decide qué hacer ante el fallo es la pantalla: `SoloExperto`
        // niega el paso, y otra podría querer reintentar.
        final container = contenedor(
          RolesFalso()..error = StateError('sin red'),
        );

        await expectLater(
          container.read(esExpertoProvider.future),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  test('una fila que no cuadra con el modelo no se disimula', () async {
    final supabase = _SupabaseFalso(
      filasLeidas: const [
        {'rol': 'experto', 'otorgado_en': 1759412400},
      ],
    );
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.misRoles(),
      throwsA(isA<FormatException>()),
    );
  });
}

/// Cliente de Supabase que no sale a la red: anota cada petición y responde lo
/// que la prueba indique.
class _SupabaseFalso {
  _SupabaseFalso({
    this.filasLeidas = const [],
    this.usuarioActual = 'usuario-1',
  }) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final List<Map<String, Object?>> filasLeidas;

  /// La cuenta con la sesión abierta, o null para probar el caso sin sesión.
  final String? usuarioActual;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  RolesRepository get repositorio => SupabaseRolesRepository(
    cliente: cliente,
    usuarioActual: () => usuarioActual,
  );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);

    // PostgREST lee `response.request` al procesar la respuesta, así que el
    // falso la devuelve atada a su petición, igual que la red real.
    return http.Response(
      jsonEncode(filasLeidas),
      200,
      headers: const {'content-type': 'application/json'},
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
