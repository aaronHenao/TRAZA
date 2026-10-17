import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/notificacion.dart';
import 'package:traza/services/notificaciones_service.dart';

/// Pruebas del repositorio real de notificaciones (SCRUM-241, SCRUM-242).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifican las consultas que de
/// verdad salen hacia Supabase.
void main() {
  final fila = {
    'id': 'aviso-1',
    'tipo': 'ruta_publicada',
    'titulo': 'Tu ruta ya está publicada',
    'mensaje': '"Vuelta al estadio" ya la puede ver la comunidad.',
    'entidad_id': 'ruta-1',
    'leida_en': null,
    'fecha_creacion': '2026-10-17T14:00:00+00:00',
  };

  test('pide solo las del usuario, de la mas reciente', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    final avisos = await supabase.repositorio.mias();

    expect(avisos.single.tipo, TipoNotificacion.rutaPublicada);
    expect(avisos.single.leida, isFalse);

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'GET');
    expect(peticion.url.path, '/rest/v1/notificaciones');
    expect(peticion.url.queryParameters['usuario_id'], 'eq.usuario-1');
    expect(
      peticion.url.queryParameters['order'],
      startsWith('fecha_creacion.desc'),
    );
  });

  test('un tipo que esta version no conoce no tumba la bandeja', () async {
    // Cuando otra historia añada un tipo de aviso, una app sin actualizar
    // tiene que seguir mostrando el resto.
    final supabase = _SupabaseFalso(
      filas: [
        {...fila, 'id': 'aviso-raro', 'tipo': 'algo_que_vendra_despues'},
        fila,
      ],
    );
    addTearDown(supabase.cerrar);

    final avisos = await supabase.repositorio.mias();

    expect(avisos.map((aviso) => aviso.id), ['aviso-1']);
  });

  test('sin sesion no sale ninguna peticion', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.mias(),
      throwsA(isA<SesionRequeridaParaNotificacionesException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  test('el contador pide solo las que no estan leidas', () async {
    final supabase = _SupabaseFalso(filas: [fila, fila, fila]);
    addTearDown(supabase.cerrar);

    expect(await supabase.repositorio.sinLeer(), 3);

    final peticion = supabase.peticiones.single;
    expect(peticion.url.queryParameters['leida_en'], 'is.null');
    expect(peticion.url.queryParameters['select'], 'id');
  });

  test('marcar como leidas solo toca las que faltaban', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    await supabase.repositorio.marcarTodasLeidas();

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'PATCH');
    expect(peticion.url.queryParameters['usuario_id'], 'eq.usuario-1');
    // Las que ya estaban leídas no se vuelven a fechar.
    expect(peticion.url.queryParameters['leida_en'], 'is.null');
    // Y no se manda nada más que esa columna: el trigger
    // `notificaciones_solo_leida` no dejaría cambiar el resto.
    expect(jsonDecode(peticion.body), isA<Map<String, Object?>>());
    expect((jsonDecode(peticion.body) as Map).keys, ['leida_en']);
  });
}

/// Cliente de Supabase que no sale a la red.
class _SupabaseFalso {
  _SupabaseFalso({this.filas = const [], this.usuarioActual = 'usuario-1'}) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final List<Map<String, Object?>> filas;
  final String? usuarioActual;
  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  NotificacionesRepository get repositorio =>
      SupabaseNotificacionesRepository(
        cliente: cliente,
        usuarioActual: () => usuarioActual,
      );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);

    return http.Response(
      jsonEncode(filas),
      200,
      headers: const {'content-type': 'application/json'},
      request: peticion,
    );
  }

  Future<void> cerrar() => cliente.dispose();
}
