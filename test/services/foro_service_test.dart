import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/reporte_foro.dart';
import 'package:traza/services/foro_service.dart';

/// Pruebas del repositorio real del foro (SCRUM-343).
///
/// No hay base de datos: un cliente HTTP falso intercepta lo que el
/// repositorio le manda a PostgREST, así se verifican las consultas que de
/// verdad salen hacia Supabase.
void main() {
  final fila = {
    'id': 'pub-1',
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'titulo': 'Tenis',
    'contenido': '¿Cuáles?',
    'estado': 'publicada',
    'motivo_moderacion': null,
    'fecha_creacion': '2026-10-16T14:00:00+00:00',
  };

  final nueva = const BorradorPublicacion(
    titulo: 'Tenis',
    contenido: '¿Cuáles?',
  ).aNuevaPublicacion()!;

  test('publica a nombre del usuario sin mandar nombre ni estado', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    final creada = await supabase.repositorio.crear(nueva);

    expect(creada.autorNombre, 'Ana');
    final peticion = supabase.peticiones.single;
    expect(peticion.method, 'POST');
    expect(peticion.url.path, '/rest/v1/publicaciones_foro');
    expect(jsonDecode(peticion.body), {
      'titulo': 'Tenis',
      'contenido': '¿Cuáles?',
      'autor_id': 'usuario-1',
    });
  });

  test('el foro pide lo publicado y lo propio en revisión, lo más reciente '
      'primero (SCRUM-322)', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    final lista = await supabase.repositorio.publicadas();

    expect(lista.single.estado, EstadoPublicacion.publicada);
    final consulta = supabase.peticiones.single.url.queryParameters;
    expect(
      consulta['or'],
      '(estado.eq.publicada,'
      'and(autor_id.eq.usuario-1,estado.in.(en_revision,pendiente)))',
    );
    expect(consulta['order'], startsWith('fecha_creacion.desc'));
    // Los comentarios que esperan la moderación no se cuentan.
    expect(consulta['comentarios_foro.estado'], 'eq.publicada');
  });

  test('sabe qué publicaciones escribió el administrador', () async {
    final supabase = _SupabaseFalso(
      filas: [
        {...fila, 'autor_es_admin': true},
        // Antes de 0023 la columna no existía.
        {...fila, 'id': 'pub-2'},
      ],
    );
    addTearDown(supabase.cerrar);

    final lista = await supabase.repositorio.publicadas();

    expect(lista.map((p) => p.autorEsAdmin), [true, false]);
  });

  test('la moderación no filtra por estado', () async {
    final supabase = _SupabaseFalso(filas: [fila]);
    addTearDown(supabase.cerrar);

    await supabase.repositorio.todasParaModeracion();

    expect(
      supabase.peticiones.single.url.queryParameters.keys,
      isNot(contains('estado')),
    );
  });

  test('el foro trae cuántos comentarios tiene cada publicación', () async {
    final supabase = _SupabaseFalso(
      filas: [
        {
          ...fila,
          'comentarios_foro': [
            {'count': 3},
          ],
        },
      ],
    );
    addTearDown(supabase.cerrar);

    final lista = await supabase.repositorio.publicadas();

    expect(
      supabase.peticiones.single.url.queryParameters['select'],
      contains('comentarios_foro(count)'),
    );
    expect(lista.single.numeroComentarios, 3);
  });

  group('comentarios (SCRUM-350)', () {
    final filaComentario = {
      'id': 'com-1',
      'publicacion_id': 'pub-1',
      'autor_id': 'usuario-1',
      'autor_nombre': 'Ana',
      'contenido': 'Buen dato',
      'fecha_creacion': '2026-10-16T15:00:00+00:00',
    };
    final nuevo = const BorradorComentario(
      'Buen dato',
    ).aNuevoComentario('pub-1')!;

    test('comenta a nombre del usuario sin mandar su nombre', () async {
      final supabase = _SupabaseFalso(filas: [filaComentario]);
      addTearDown(supabase.cerrar);

      final comentario = await supabase.repositorio.comentar(nuevo);

      expect(comentario.autorNombre, 'Ana');
      final peticion = supabase.peticiones.single;
      expect(peticion.url.path, '/rest/v1/comentarios_foro');
      expect(jsonDecode(peticion.body), {
        'publicacion_id': 'pub-1',
        'contenido': 'Buen dato',
        'autor_id': 'usuario-1',
      });
    });

    test(
      'lee los comentarios de una publicación en orden de llegada',
      () async {
        final supabase = _SupabaseFalso(filas: [filaComentario]);
        addTearDown(supabase.cerrar);

        final lista = await supabase.repositorio.comentarios('pub-1');

        expect(lista.single.contenido, 'Buen dato');
        final consulta = supabase.peticiones.single.url.queryParameters;
        expect(consulta['publicacion_id'], 'eq.pub-1');
        expect(consulta['order'], startsWith('fecha_creacion.asc'));
      },
    );

    test('sabe qué comentarios escribió el administrador', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {...filaComentario, 'autor_es_admin': true},
          {...filaComentario, 'id': 'com-2', 'autor_es_admin': false},
          // Antes de 0022 la columna no existía.
          {...filaComentario, 'id': 'com-3'},
        ],
      );
      addTearDown(supabase.cerrar);

      final lista = await supabase.repositorio.comentarios('pub-1');

      expect(lista.map((c) => c.autorEsAdmin), [true, false, false]);
    });

    test('al editar propone el texto a la moderación con '
        'editar_comentario_foro (SCRUM-322)', () async {
      final supabase = _SupabaseFalso(
        respuestaRpc: {
          ..._filaModeracion,
          'tipo': 'comentario',
          'comentario_id': 'com-1',
          'accion': 'edicion',
          'titulo': null,
          'contenido': 'Buen dato',
          'estado': 'en_revision',
        },
      );
      addTearDown(supabase.cerrar);

      final moderacion = await supabase.repositorio.editarComentario(
        'com-1',
        nuevo,
      );

      expect(moderacion?.estado, EstadoModeracion.enRevision);
      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/editar_comentario_foro');
      expect(jsonDecode(peticion.body), {
        'p_id': 'com-1',
        'p_contenido': 'Buen dato',
      });
    });

    test('si no es suyo o la publicación ya no está, no está disponible', () {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.editarComentario('com-1', nuevo),
        throwsA(isA<PublicacionNoDisponibleException>()),
      );
    });

    test('si ya tiene una edición esperando, lo dice (TZ409)', () {
      final supabase = _SupabaseFalso(codigoPostgres: 'TZ409');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.editarComentario('com-1', nuevo),
        throwsA(isA<EdicionYaEnRevisionException>()),
      );
    });

    test('lee el estado de moderación de cada comentario', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {...filaComentario, 'estado': 'en_revision'},
          // Antes de 0035 la columna no existía: estaba publicado.
          {...filaComentario, 'id': 'com-2'},
        ],
      );
      addTearDown(supabase.cerrar);

      final lista = await supabase.repositorio.comentarios('pub-1');

      expect(lista.map((c) => c.estado), [
        EstadoPublicacion.enRevision,
        EstadoPublicacion.publicada,
      ]);
    });

    test('sabe si un comentario fue editado y lee su historial', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {...filaComentario, 'fecha_edicion': '2026-10-16T16:00:00+00:00'},
        ],
      );
      addTearDown(supabase.cerrar);

      final lista = await supabase.repositorio.comentarios('pub-1');
      expect(lista.single.editado, isTrue);

      final historial = _SupabaseFalso(
        filas: [
          {
            'id': 'vc-1',
            'comentario_id': 'com-1',
            'contenido': 'Antes',
            'vigente_desde': '2026-10-16T15:00:00+00:00',
            'reemplazada_en': '2026-10-16T16:00:00+00:00',
          },
        ],
      );
      addTearDown(historial.cerrar);

      final versiones = await historial.repositorio.versionesComentario(
        'com-1',
      );

      expect(versiones.single.contenido, 'Antes');
      final consulta = historial.peticiones.single.url;
      expect(consulta.path, '/rest/v1/versiones_comentario_foro');
      expect(consulta.queryParameters['comentario_id'], 'eq.com-1');
    });

    for (final (codigo, causa) in [
      ('42501', 'la publicación ya no está publicada'),
      ('23503', 'la publicación ya no existe'),
    ]) {
      test('si $causa ($codigo), la publicación no está disponible', () async {
        final supabase = _SupabaseFalso(codigoPostgres: codigo);
        addTearDown(supabase.cerrar);

        expect(
          () => supabase.repositorio.comentar(nuevo),
          throwsA(isA<PublicacionNoDisponibleException>()),
        );
      });
    }
  });

  group('editar (SCRUM-355)', () {
    test('propone el título y el contenido a la moderación con '
        'editar_publicacion_foro (SCRUM-322)', () async {
      final supabase = _SupabaseFalso(
        respuestaRpc: {
          ..._filaModeracion,
          'accion': 'edicion',
          'estado': 'en_revision',
        },
      );
      addTearDown(supabase.cerrar);

      final moderacion = await supabase.repositorio.editar('pub-1', nueva);

      expect(moderacion?.esEdicion, isTrue);
      expect(moderacion?.abierta, isTrue);
      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/rpc/editar_publicacion_foro');
      expect(jsonDecode(peticion.body), {
        'p_id': 'pub-1',
        'p_titulo': 'Tenis',
        'p_contenido': '¿Cuáles?',
      });
    });

    for (final (descripcion, respuesta) in [
      ('null', null),
      ('la fila con todo en null', {'id': null, 'estado': null}),
    ]) {
      test('si el texto no cambió, la base devuelve $descripcion y no hay '
          'moderación', () async {
        final supabase = _SupabaseFalso(respuestaRpc: respuesta);
        addTearDown(supabase.cerrar);

        expect(await supabase.repositorio.editar('pub-1', nueva), isNull);
      });
    }

    test('si ya tiene una edición esperando, lo dice (TZ409)', () {
      final supabase = _SupabaseFalso(codigoPostgres: 'TZ409');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.editar('pub-1', nueva),
        throwsA(isA<EdicionYaEnRevisionException>()),
      );
    });

    test('lee el historial de la más reciente a la original', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {
            'id': 'ver-1',
            'publicacion_id': 'pub-1',
            'titulo': 'Tenis',
            'contenido': 'Antes',
            'vigente_desde': '2026-10-16T14:00:00+00:00',
            'reemplazada_en': '2026-10-16T15:00:00+00:00',
          },
        ],
      );
      addTearDown(supabase.cerrar);

      final versiones = await supabase.repositorio.versiones('pub-1');

      expect(versiones.single.contenido, 'Antes');
      final consulta = supabase.peticiones.single.url;
      expect(consulta.path, '/rest/v1/versiones_publicacion_foro');
      expect(consulta.queryParameters['publicacion_id'], 'eq.pub-1');
      expect(
        consulta.queryParameters['order'],
        startsWith('reemplazada_en.desc'),
      );
    });

    test('sabe si una publicación fue editada', () async {
      final supabase = _SupabaseFalso(
        filas: [
          {...fila, 'fecha_edicion': '2026-10-16T16:00:00+00:00'},
          {...fila, 'id': 'pub-2'},
        ],
      );
      addTearDown(supabase.cerrar);

      final lista = await supabase.repositorio.publicadas();

      expect(lista.map((p) => p.editada), [true, false]);
    });

    for (final (codigo, causa) in [
      ('PGRST116', 'la policy no dejó tocar la fila'),
      ('42501', 'la seguridad a nivel de fila lo negó'),
    ]) {
      test('si $causa ($codigo), la publicación no está disponible', () async {
        final supabase = _SupabaseFalso(codigoPostgres: codigo);
        addTearDown(supabase.cerrar);

        expect(
          () => supabase.repositorio.editar('pub-1', nueva),
          throwsA(isA<PublicacionNoDisponibleException>()),
        );
      });
    }
  });

  test('si la tabla rechaza los datos lo dice con su excepción', () async {
    final supabase = _SupabaseFalso(codigoPostgres: '23514');
    addTearDown(supabase.cerrar);

    expect(
      () => supabase.repositorio.crear(nueva),
      throwsA(isA<DatosDePublicacionInvalidosException>()),
    );
  });

  group('moderación (SCRUM-322)', () {
    test(
      'lo propio se pide filtrado por autor, lo más reciente primero',
      () async {
        final supabase = _SupabaseFalso(filas: [_filaModeracion]);
        addTearDown(supabase.cerrar);

        final lista = await supabase.repositorio.misModeraciones();

        expect(lista.single.rechazada, isTrue);
        final consulta = supabase.peticiones.single.url;
        expect(consulta.path, '/rest/v1/moderaciones_foro');
        expect(consulta.queryParameters['autor_id'], 'eq.usuario-1');
        expect(
          consulta.queryParameters['order'],
          startsWith('fecha_solicitud.desc'),
        );
      },
    );

    test('el administrador pide toda la moderación', () async {
      final supabase = _SupabaseFalso(filas: [_filaModeracion]);
      addTearDown(supabase.cerrar);

      await supabase.repositorio.moderaciones();

      expect(
        supabase.peticiones.single.url.queryParameters.keys,
        isNot(contains('autor_id')),
      );
    });

    test(
      'lee quién la decidió, cuándo, por qué y el tipo de infracción',
      () async {
        final supabase = _SupabaseFalso(filas: [_filaModeracion]);
        addTearDown(supabase.cerrar);

        final m = (await supabase.repositorio.moderaciones()).single;

        expect(m.tipo, TipoModeracion.publicacion);
        expect(m.accion, AccionModeracion.creacion);
        expect(m.motivo, 'Spam');
        expect(m.categorias, ['Spam']);
        expect(m.responsable, ResponsableModeracion.ia);
        expect(m.responsableParaElAutor, 'Moderación automática');
        expect(m.fechaDecision?.toUtc(), DateTime.utc(2026, 10, 16, 14, 0, 7));
        expect(m.vistaPorAutor, isFalse);
      },
    );

    test(
      'decidir llama a decidir_moderacion con la decisión y el motivo',
      () async {
        final supabase = _SupabaseFalso(respuestaRpc: _filaModeracion);
        addTearDown(supabase.cerrar);

        await supabase.repositorio.decidir(
          'mod-1',
          aprobar: false,
          motivo: 'Spam',
        );

        final peticion = supabase.peticiones.single;
        expect(peticion.url.path, '/rest/v1/rpc/decidir_moderacion');
        expect(jsonDecode(peticion.body), {
          'p_moderacion_id': 'mod-1',
          'p_aprobar': false,
          'p_motivo': 'Spam',
        });
      },
    );

    test('si alguien la resolvió antes, lo dice (TZ409)', () {
      final supabase = _SupabaseFalso(codigoPostgres: 'TZ409');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.decidir('mod-1', aprobar: true),
        throwsA(isA<ModeracionYaResueltaException>()),
      );
    });

    test('marcar los rechazos como vistos llama a su función', () async {
      final supabase = _SupabaseFalso(respuestaRpc: 1);
      addTearDown(supabase.cerrar);

      await supabase.repositorio.marcarRechazosVistos();

      expect(
        supabase.peticiones.single.url.path,
        '/rest/v1/rpc/marcar_rechazos_vistos',
      );
    });

    test('una fila con un estado desconocido no se acepta', () {
      expect(
        () => ModeracionForo.desdeSupabase({
          ..._filaModeracion,
          'estado': 'retenida',
        }),
        throwsFormatException,
      );
    });
  });

  test('sin sesión no sale ninguna petición', () async {
    final supabase = _SupabaseFalso(usuarioActual: null);
    addTearDown(supabase.cerrar);

    expect(
      () => supabase.repositorio.crear(nueva),
      throwsA(isA<SesionRequeridaParaForoException>()),
    );
    expect(supabase.peticiones, isEmpty);
  });

  group('reportes (SCRUM-369)', () {
    test('reportar registra la publicación y el motivo a nombre del usuario '
        'de la sesión, sin pedir la fila de vuelta (criterio 1 de '
        'SCRUM-369)', () async {
      final supabase = _SupabaseFalso();
      addTearDown(supabase.cerrar);

      await supabase.repositorio.reportar(
        'pub-1',
        MotivoReporte.acoso,
        detalle: '  Insulta a otro corredor  ',
      );

      final peticion = supabase.peticiones.single;
      expect(peticion.method, 'POST');
      expect(peticion.url.path, '/rest/v1/reportes_foro');
      expect(jsonDecode(peticion.body), {
        'publicacion_id': 'pub-1',
        'reportante_id': 'usuario-1',
        'motivo': 'acoso',
        'detalle': 'Insulta a otro corredor',
      });
      // Sin `select`: lo que vuelve tendría quién reportó, y no hace falta.
      expect(peticion.url.queryParameters.keys, isNot(contains('select')));
    });

    for (final (descripcion, detalle) in [
      ('sin detalle', null),
      ('con un detalle de solo espacios', '   '),
    ]) {
      test('$descripcion, el detalle va vacío (null)', () async {
        final supabase = _SupabaseFalso();
        addTearDown(supabase.cerrar);

        await supabase.repositorio.reportar(
          'pub-1',
          MotivoReporte.spam,
          detalle: detalle,
        );

        expect(jsonDecode(supabase.peticiones.single.body), {
          'publicacion_id': 'pub-1',
          'reportante_id': 'usuario-1',
          'motivo': 'spam',
          'detalle': null,
        });
      });
    }

    test('si ya la reportó, el unique de la base lo impide y lo dice '
        '(23505, criterio 3 de SCRUM-369)', () {
      final supabase = _SupabaseFalso(codigoPostgres: '23505');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.reportar('pub-1', MotivoReporte.spam),
        throwsA(isA<PublicacionYaReportadaException>()),
      );
    });

    test('si la policy lo rechaza (ya no está publicada o es propia), la '
        'publicación no está disponible (42501)', () {
      final supabase = _SupabaseFalso(codigoPostgres: '42501');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.reportar('pub-1', MotivoReporte.spam),
        throwsA(isA<PublicacionNoDisponibleException>()),
      );
    });

    test('si la publicación se borró antes de reportarla, no está '
        'disponible (23503)', () {
      final supabase = _SupabaseFalso(codigoPostgres: '23503');
      addTearDown(supabase.cerrar);

      expect(
        () => supabase.repositorio.reportar('pub-1', MotivoReporte.spam),
        throwsA(isA<PublicacionNoDisponibleException>()),
      );
    });

    test('sin sesión no se piden los reportes', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        supabase.repositorio.reportes,
        throwsA(isA<SesionRequeridaParaForoException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test('sin sesión no sale ningún reporte', () async {
      final supabase = _SupabaseFalso(usuarioActual: null);
      addTearDown(supabase.cerrar);

      await expectLater(
        () => supabase.repositorio.reportar('pub-1', MotivoReporte.spam),
        throwsA(isA<SesionRequeridaParaForoException>()),
      );
      expect(supabase.peticiones, isEmpty);
    });

    test(
      'el administrador pide los reportes con su publicación y sin quién '
      'los envió, el más reciente primero (criterio 2 de SCRUM-369)',
      () async {
        final supabase = _SupabaseFalso(
          filas: [
            {
              'id': 'rep-1',
              'publicacion_id': 'pub-1',
              'motivo': 'acoso',
              'detalle': 'Insulta a otro corredor',
              'fecha': '2026-10-16T14:00:00+00:00',
              'publicaciones_foro': {
                'titulo': 'Tenis',
                'autor_nombre': 'Carlos',
              },
            },
          ],
        );
        addTearDown(supabase.cerrar);

        final reportes = await supabase.repositorio.reportes();

        final reporte = reportes.single;
        expect(reporte.motivo, MotivoReporte.acoso);
        expect(reporte.tituloPublicacion, 'Tenis');
        expect(reporte.autorPublicacion, 'Carlos');
        final consulta = supabase.peticiones.single.url;
        expect(consulta.path, '/rest/v1/reportes_foro');
        expect(
          consulta.queryParameters['select'],
          'id,publicacion_id,motivo,detalle,fecha,'
          'publicaciones_foro!inner(titulo,autor_nombre)',
        );
        expect(
          consulta.queryParameters['select'],
          isNot(contains('reportante')),
        );
        // SCRUM-242: los de lo retirado salen de la bandeja. El `!inner` es
        // lo que hace que el filtro descarte el reporte en vez de devolverlo
        // con la publicación vacía.
        expect(
          consulta.queryParameters['publicaciones_foro.estado'],
          'neq.${EstadoPublicacion.eliminada.valorDb}',
        );
        expect(consulta.queryParameters.keys, isNot(contains('reportante_id')));
        expect(consulta.queryParameters['order'], startsWith('fecha.desc'));
        expect(
          consulta.queryParameters['limit'],
          '${SupabaseForoRepository.limiteModeracion}',
        );
      },
    );
  });
}

/// Una fila de `moderaciones_foro`: una publicación que la IA rechazó por
/// spam.
const _filaModeracion = <String, Object?>{
  'id': 'mod-1',
  'tipo': 'publicacion',
  'publicacion_id': 'pub-1',
  'comentario_id': null,
  'autor_id': 'usuario-1',
  'autor_nombre': 'Ana',
  'accion': 'creacion',
  'titulo': 'Compra ya',
  'contenido': 'Descuentos en www.tenis.shop',
  'estado': 'rechazada',
  'motivo': 'Spam',
  'categorias': ['Spam'],
  'responsable': 'ia',
  'responsable_id': null,
  'responsable_nombre': 'Moderación automática',
  'veredicto_ia': {'modelo': 'nvidia/nemotron-3.5-content-safety'},
  'fecha_solicitud': '2026-10-16T14:00:00+00:00',
  'fecha_decision': '2026-10-16T14:00:07+00:00',
  'vista_por_autor': false,
};

/// Cliente de Supabase que no sale a la red.
class _SupabaseFalso {
  _SupabaseFalso({
    this.filas = const [],
    this.codigoPostgres,
    this.usuarioActual = 'usuario-1',
    this.respuestaRpc,
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

  /// Lo que devuelven las funciones (`/rpc/...`), tal cual.
  final Object? respuestaRpc;
  final peticiones = <http.Request>[];

  late final SupabaseClient cliente;

  ForoRepository get repositorio => SupabaseForoRepository(
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

    if (peticion.url.path.startsWith('/rest/v1/rpc/')) {
      return http.Response(
        jsonEncode(respuestaRpc),
        200,
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
