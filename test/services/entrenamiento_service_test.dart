import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;

/// Pruebas del repositorio real de entrenamientos: el cierre (SCRUM-121) y la
/// lectura del entrenamiento finalizado para el resumen (SCRUM-118).
///
/// Igual que en las de objetivos, no hay base de datos: un cliente HTTP falso
/// intercepta la petición que el repositorio le manda a PostgREST y responde lo
/// que la prueba necesita. Así se verifican las consultas que de verdad salen
/// hacia Supabase.
void main() {
  test('crea el entrenamiento en curso del usuario y devuelve su id', () async {
    final supabase = _SupabaseFalso(
      filasActualizadas: [
        {'id': 'e-nuevo'},
      ],
    );
    addTearDown(supabase.cerrar);

    final id = await supabase.repositorio.crear(tipoActividadId: 'id-correr');

    expect(id, 'e-nuevo');
    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/entrenamientos');
    // Pide el id de vuelta: lo genera la base y sin él no habría con qué
    // guardar los puntos ni cerrar el entrenamiento.
    expect(peticion.url.queryParameters['select'], 'id');
    expect(jsonDecode(peticion.body), {
      'usuario_id': 'usuario-1',
      'tipo_actividad_id': 'id-correr',
      'estado': 'en_curso',
    });
  });

  test(
    'no manda fecha_inicio: la pone la base con la hora del servidor',
    () async {
      final supabase = _SupabaseFalso(
        filasActualizadas: [
          {'id': 'e-nuevo'},
        ],
      );
      addTearDown(supabase.cerrar);

      await supabase.repositorio.crear(tipoActividadId: 'id-correr');

      expect(
        (jsonDecode(supabase.peticiones.single.body) as Map).keys,
        isNot(contains('fecha_inicio')),
      );
    },
  );

  test('sin sesión no intenta crear el entrenamiento', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.crear(tipoActividadId: 'id-correr'),
      throwsA(isA<SesionRequeridaException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  test('si la base rechaza la creación, el error sale a la vista', () async {
    final supabase = _SupabaseFalso(codigoError: 401);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.crear(tipoActividadId: 'id-correr'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('descarta el entrenamiento dejandolo cancelado', () async {
    final supabase = _SupabaseFalso(
      filasActualizadas: [
        {'id': 'e-123'},
      ],
    );
    addTearDown(supabase.cerrar);

    await supabase.repositorio.cancelar(
      entrenamientoId: 'e-123',
      fechaFin: DateTime.utc(2026, 1, 1, 13, 5),
    );

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'PATCH');
    expect(peticion.url.queryParameters['id'], 'eq.e-123');
    // Solo toca el que sigue en curso: uno ya finalizado no se descarta.
    expect(peticion.url.queryParameters['estado'], 'eq.en_curso');
    expect(jsonDecode(peticion.body), {
      'fecha_fin': '2026-01-01T13:05:00.000Z',
      'estado': 'cancelado',
    });
  });

  test('si el entrenamiento a descartar ya no está en curso, avisa', () async {
    final supabase = _SupabaseFalso(filasActualizadas: []);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.cancelar(
        entrenamientoId: 'e-123',
        fechaFin: DateTime.utc(2026, 1, 1, 13, 5),
      ),
      throwsA(isA<EntrenamientoNoEncontradoException>()),
    );
  });

  test('cierra el entrenamiento con fecha_fin, duración, distancia y estado '
      'finalizado', () async {
    final supabase = _SupabaseFalso(
      filasActualizadas: [
        {'id': 'e-123'},
      ],
    );
    addTearDown(supabase.cerrar);

    await supabase.repositorio.finalizar(
      entrenamientoId: 'e-123',
      fechaFin: DateTime.utc(2026, 1, 1, 13, 32, 17),
      duracion: const Duration(minutes: 32, seconds: 17, milliseconds: 800),
      distanciaMetros: 5230.5,
    );

    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'PATCH');
    expect(peticion.url.path, '/rest/v1/entrenamientos');
    expect(peticion.url.queryParameters['id'], 'eq.e-123');
    // Pide de vuelta las filas actualizadas para comprobar que hubo una.
    expect(peticion.url.queryParameters['select'], 'id');
    expect(jsonDecode(peticion.body), {
      'fecha_fin': '2026-01-01T13:32:17.000Z',
      // Los segundos completos: el cronómetro muestra 00:32:17.
      'duracion_segundos': 1937,
      'distancia_total_m': 5230.5,
      'estado': 'finalizado',
    });
  });

  test('sin distancia calculada deja distancia_total_m vacía', () async {
    final supabase = _SupabaseFalso(
      filasActualizadas: [
        {'id': 'e-123'},
      ],
    );
    addTearDown(supabase.cerrar);

    await supabase.repositorio.finalizar(
      entrenamientoId: 'e-123',
      fechaFin: DateTime.utc(2026, 1, 1, 13),
      duracion: const Duration(minutes: 5),
    );

    final cuerpo = jsonDecode(supabase.peticiones.single.body) as Map;
    expect(cuerpo.containsKey('distancia_total_m'), isTrue);
    expect(cuerpo['distancia_total_m'], isNull);
  });

  test('si no actualizó ninguna fila lo reporta como error', () async {
    // Id inexistente o fila de otro usuario: PostgREST responde bien, pero
    // vacío.
    final supabase = _SupabaseFalso(filasActualizadas: []);
    addTearDown(supabase.cerrar);

    await expectLater(
      supabase.repositorio.finalizar(
        entrenamientoId: 'e-otro',
        fechaFin: DateTime.utc(2026, 1, 1, 13),
        duracion: const Duration(minutes: 5),
      ),
      throwsA(
        isA<EntrenamientoNoEncontradoException>().having(
          (error) => error.entrenamientoId,
          'entrenamientoId',
          'e-otro',
        ),
      ),
    );
  });

  group('cargarFinalizado (SCRUM-118)', () {
    test('pide el entrenamiento por id, solo si está finalizado, con su '
        'actividad y sus puntos en orden', () async {
      final supabase = _SupabaseFalso(filasLeidas: [_filaGuardada]);
      addTearDown(supabase.cerrar);

      final resumen = await supabase.repositorio.cargarFinalizado('e-123');

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'GET');
      expect(peticion.url.path, '/rest/v1/entrenamientos');
      final parametros = peticion.url.queryParameters;
      expect(parametros['id'], 'eq.e-123');
      expect(parametros['estado'], 'eq.finalizado');
      expect(parametros['select'], contains('tipos_actividad(nombre)'));
      expect(parametros['select'], contains('puntos_gps('));
      expect(parametros['select'], contains('tramo'));
      expect(parametros['puntos_gps.order'], 'orden_secuencia.asc.nullslast');

      expect(resumen, isNotNull);
      expect(resumen!.entrenamientoId, 'e-123');
      expect(resumen.nombreActividad, 'Trote');
      expect(resumen.fechaFin, DateTime.utc(2026, 1, 1, 13, 32, 17));
      expect(resumen.duracion, const Duration(seconds: 1937));
      expect(resumen.distanciaMetros, 5230.5);
      expect(resumen.puntos.map((punto) => punto.latitud), [6.2311, 6.0]);
      expect(resumen.puntos.first.capturadoEn, DateTime.utc(2026, 1, 1, 13));
      // Filas sin `tramo` (anteriores a la migración 0005): un solo tramo.
      expect(resumen.cortes, isEmpty);
    });

    test('reconstruye dónde empieza cada tramo con la columna tramo '
        '(BUG-005)', () async {
      Map<String, Object?> fila(int orden, int tramo) => {
        'latitud': 6.2311 + orden / 1000,
        'longitud': -75.6105,
        'capturado_en': '2026-01-01T13:00:0$orden+00:00',
        'orden_secuencia': orden,
        'tramo': tramo,
      };
      final supabase = _SupabaseFalso(
        filasLeidas: [
          {
            ..._filaGuardada,
            'puntos_gps': [fila(0, 0), fila(1, 0), fila(2, 1), fila(3, 1)],
          },
        ],
      );
      addTearDown(supabase.cerrar);

      final resumen = await supabase.repositorio.cargarFinalizado('e-123');

      expect(resumen!.puntos, hasLength(4));
      expect(resumen.cortes, [2]);
    });

    test('si no existe, no es del usuario o no está finalizado devuelve '
        'null', () async {
      // PostgREST responde bien, pero sin filas.
      final supabase = _SupabaseFalso(filasLeidas: []);
      addTearDown(supabase.cerrar);

      expect(await supabase.repositorio.cargarFinalizado('e-123'), isNull);
    });

    test('sin distancia guardada la deja vacía', () async {
      final supabase = _SupabaseFalso(
        filasLeidas: [
          {..._filaGuardada, 'distancia_total_m': null},
        ],
      );
      addTearDown(supabase.cerrar);

      final resumen = await supabase.repositorio.cargarFinalizado('e-123');

      expect(resumen!.distanciaMetros, isNull);
    });

    test('si Supabase responde con error lo lanza', () async {
      final supabase = _SupabaseFalso(codigoError: 400);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.cargarFinalizado('e-123'),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}

/// Un entrenamiento finalizado tal como lo devuelve PostgREST, con su tipo de
/// actividad y sus puntos.
const _filaGuardada = <String, Object?>{
  'id': 'e-123',
  'fecha_fin': '2026-01-01T13:32:17+00:00',
  'duracion_segundos': 1937,
  // `numeric` puede llegar como texto.
  'distancia_total_m': '5230.5',
  'tipos_actividad': {'nombre': 'Trote'},
  'puntos_gps': [
    {
      'latitud': 6.2311,
      'longitud': -75.6105,
      'capturado_en': '2026-01-01T13:00:00+00:00',
      'orden_secuencia': 0,
    },
    // Un número entero en JSON también es una coordenada válida.
    {
      'latitud': 6,
      'longitud': -75.61,
      'capturado_en': '2026-01-01T13:00:05+00:00',
      'orden_secuencia': 1,
    },
  ],
};

/// Cliente de Supabase que no sale a la red: anota cada petición y responde
/// [filasLeidas] a las lecturas y [filasActualizadas] a las actualizaciones, o
/// un error si se indica [codigoError].
class _SupabaseFalso {
  _SupabaseFalso({
    this.filasActualizadas = const [],
    this.filasLeidas = const [],
    this.codigoError,
    this.usuarioActual = 'usuario-1',
  }) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  final List<Map<String, Object?>> filasActualizadas;
  final List<Map<String, Object?>> filasLeidas;

  /// Quién tiene la sesión abierta. Null simula que no hay ninguna.
  final String? usuarioActual;

  /// Un código que PostgREST no reintenta (solo reintenta 503 y 520).
  final int? codigoError;

  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  EntrenamientoRepository get repositorio => SupabaseEntrenamientoRepository(
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
        jsonEncode({'message': 'Error de prueba', 'code': 'PGRST000'}),
        codigoError,
        headers: encabezados,
        request: peticion,
      );
    }
    final filas = peticion.method == 'GET' ? filasLeidas : filasActualizadas;
    // `single` y `maybeSingle` piden una fila suelta con este Accept, y
    // PostgREST les responde con el objeto, no con una lista.
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
