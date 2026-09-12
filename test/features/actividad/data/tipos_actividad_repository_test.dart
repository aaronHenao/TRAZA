import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/features/actividad/data/tipos_actividad_repository.dart';
import 'package:traza/features/actividad/domain/tipo_actividad.dart';

/// Pruebas del repositorio real de tipos de actividad (SCRUM-92), con la red
/// reemplazada por un cliente HTTP falso, igual que las del repositorio de
/// objetivos.
void main() {
  test('con sesión lee id y nombre de tipos_actividad', () async {
    final supabase = _SupabaseFalso([
      {'id': 'id-correr', 'nombre': 'Correr'},
      {'id': 'id-trote', 'nombre': 'Trote'},
    ]);
    addTearDown(supabase.cerrar);

    final tipos = await supabase.repositorio(usuarioId: 'usuario').cargar();

    expect(tipos.map((tipo) => tipo.id), ['id-correr', 'id-trote']);

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'GET');
    expect(peticion.url.path, '/rest/v1/tipos_actividad');
    expect(peticion.url.queryParameters['select'], 'id,nombre');
  });

  test('ordena como el prototipo y deja al final los tipos que no conoce', () async {
    final supabase = _SupabaseFalso([
      {'id': '1', 'nombre': 'Caminar'},
      {'id': '2', 'nombre': 'Nadar'},
      {'id': '3', 'nombre': 'Correr'},
      {'id': '4', 'nombre': 'Bicicleta'},
      {'id': '5', 'nombre': 'Trote'},
    ]);
    addTearDown(supabase.cerrar);

    final tipos = await supabase.repositorio(usuarioId: 'usuario').cargar();

    expect(tipos.map((tipo) => tipo.nombre), [
      'Correr',
      'Trote',
      'Caminar',
      'Bicicleta',
      'Nadar',
    ]);
  });

  test('sin sesión devuelve el catálogo local sin tocar la red', () async {
    final supabase = _SupabaseFalso(const []);
    addTearDown(supabase.cerrar);

    final tipos = await supabase.repositorio(usuarioId: null).cargar();

    expect(tipos.map((tipo) => tipo.nombre), ['Correr', 'Trote', 'Caminar']);
    // Sin id nadie puede crear un entrenamiento con estos tipos por error.
    expect(tipos.every((tipo) => tipo.id == null), isTrue);
    expect(supabase.peticiones, isEmpty);
  });

  test('con sesión y el catálogo vacío no inventa tipos', () async {
    final supabase = _SupabaseFalso(const []);
    addTearDown(supabase.cerrar);

    expect(await supabase.repositorio(usuarioId: 'usuario').cargar(), isEmpty);
  });

  test('dos tipos con el mismo nombre son el mismo aunque cambie el id', () {
    expect(
      const TipoActividad(id: null, nombre: 'Correr'),
      const TipoActividad(id: 'id-correr', nombre: 'Correr'),
    );
  });
}

/// Un [SupabaseClient] de verdad, pero con la red reemplazada: registra cada
/// petición y responde con [filas], como lo haría PostgREST.
class _SupabaseFalso {
  _SupabaseFalso(this.filas) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final List<Map<String, Object?>> filas;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  TiposActividadRepository repositorio({required String? usuarioId}) =>
      SupabaseTiposActividadRepository(
        cliente: cliente,
        usuarioActual: () => usuarioId,
      );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    // PostgREST lee `response.request` al procesar la respuesta, así que el
    // falso la devuelve atada a su petición, igual que la red real.
    return http.Response(
      jsonEncode(filas),
      200,
      headers: {'content-type': 'application/json'},
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
