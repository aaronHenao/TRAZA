import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';

/// Pruebas del repositorio real de permisos (SCRUM-80).
///
/// Igual que en objetivos: un cliente HTTP falso intercepta lo que se le manda
/// a PostgREST, así se verifica la tabla y el upsert sin base de datos.
void main() {
  const usuarioId = 'usuario-de-prueba';

  late List<http.Request> peticiones;
  late SupabaseClient cliente;

  setUp(() {
    peticiones = [];
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((peticion) async {
        peticiones.add(peticion);
        return http.Response('', 201, request: peticion);
      }),
    );
    addTearDown(cliente.dispose);
  });

  SupabasePermisosUsuarioRepository repositorio(String? usuario) =>
      SupabasePermisosUsuarioRepository(
        cliente: cliente,
        usuarioActual: () => usuario,
      );

  test('hace upsert sobre (usuario_id, tipo_permiso)', () async {
    await repositorio(
      usuarioId,
    ).guardar(TipoPermiso.ubicacion, concedido: true);

    final peticion = peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/permisos_usuario');
    expect(
      peticion.url.queryParameters['on_conflict'],
      'usuario_id,tipo_permiso',
    );
    expect(peticion.headers['Prefer'], contains('resolution=merge-duplicates'));

    final fila = jsonDecode(peticion.body) as Map<String, dynamic>;
    expect(fila['usuario_id'], usuarioId);
    expect(fila['tipo_permiso'], 'ubicacion');
    expect(fila['concedido'], isTrue);
    expect(DateTime.tryParse(fila['fecha_actualizacion'] as String), isNotNull);
  });

  test('guarda también cuando el permiso se negó', () async {
    await repositorio(usuarioId).guardar(TipoPermiso.salud, concedido: false);

    final fila = jsonDecode(peticiones.single.body) as Map<String, dynamic>;
    expect(fila['tipo_permiso'], 'salud');
    expect(fila['concedido'], isFalse);
  });

  test('sin sesión no manda nada', () async {
    await expectLater(
      repositorio(null).guardar(TipoPermiso.ubicacion, concedido: true),
      throwsA(isA<SesionRequeridaException>()),
    );
    expect(peticiones, isEmpty);
  });
}
