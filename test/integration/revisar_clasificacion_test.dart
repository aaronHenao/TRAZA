// Pruebas de integración de revisar la clasificación de una ruta (HU-35,
// SCRUM-265): que solo el rol correspondiente pueda revisar, y que confirmar
// y corregir dejen la ruta como se espera.
//
// Monta la sección de Rutas tal como la registra la app (`seccionRutas`),
// con el repositorio de verdad. Solo se reemplaza lo que necesita red o
// teléfono: Supabase contesta desde un cliente HTTP falso, como contestaría
// PostgREST, y la ubicación y los permisos salen de fuentes falsas.
//
// La base falsa cumple el contrato de `docs/deudas.md`: decide quién puede
// revisar con la regla de 0042 (Runner Experto y no autor), y
// `confirmar_clasificacion` y `corregir_clasificacion` cambian la ruta y
// anotan quién la revisó y cuándo.
//
// Lo que estas pruebas NO prueban:
// - La base de verdad. La regla de 0042 se probó contra un Postgres con las
//   migraciones reales; las funciones de confirmar y corregir todavía no
//   existen (las espera SCRUM-363).
// - Las columnas. La base falsa devuelve `dificultad` y
//   `dificultad_revisada_en` aunque la consulta de hoy no las pida: así será
//   cuando existan y se sumen a `_columnasConTrazado`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/revisar_clasificacion_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 24, 12);

  // Ana publicó la ruta. Ana y Luis son Runner Experto; Marta no.
  const ana = 'usuario-ana';
  const luis = 'usuario-luis';
  const marta = 'usuario-marta';

  late _BaseFalsa base;
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    base = _BaseFalsa(ahora: ahora.toUtc())
      ..expertos.addAll({ana, luis})
      ..rutas['ruta-1'] = _fila(
        'ruta-1',
        'Subida al Volador',
        autorId: ana,
        dificultad: Dificultad.moderada,
      );

    permisos = _MockPermisosService();
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});

    fuente = FuenteUbicacionFalsa()
      ..puntoActual = puntoDePrueba(latitud: 6.2318, longitud: -75.6105);
  });

  tearDown(() => fuente.cerrar());

  /// Abre la app como [usuario] en [ubicacion], con la sección de Rutas
  /// tal como la registra la app.
  Future<GoRouter> abrir(
    WidgetTester tester, {
    required String usuario,
    required String ubicacion,
  }) async {
    base.usuario = usuario;
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(base.cerrar);
    addTearDown(() => expect(base.inesperadas, isEmpty));

    final router = GoRouter(
      initialLocation: ubicacion,
      routes: [
        seccionRutas,
        for (final seccion in SeccionPrincipal.values)
          if (seccion != SeccionPrincipal.rutas)
            GoRoute(
              path: seccion.ruta,
              builder: (_, _) => NavegacionPrincipal(
                seccion: seccion,
                child: Text('En ${seccion.etiqueta}'),
              ),
            ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasRepositoryProvider.overrideWithValue(
            SupabaseRutasRepository(
              cliente: base.cliente,
              usuarioActual: () => base.usuario,
            ),
          ),
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _PermisosGuardadosFalso(),
          ),
          fuenteUbicacionProvider.overrideWithValue(fuente),
          relojProvider.overrideWithValue(() => ahora),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Finder botonRevisar() => find.byKey(RevisarClasificacionScreen.claveAbrir);

  Finder enLaDificultadDelDetalle(String texto) => find.descendant(
    of: find.byKey(DetalleRutaScreen.claveDificultad),
    matching: find.text(texto),
  );

  /// Del detalle a la revisión, por el botón, como el Runner Experto.
  Future<void> entrarARevisar(WidgetTester tester) async {
    await tester.tap(botonRevisar());
    await tester.pumpAndSettle();
  }

  group('solo el rol correspondiente puede revisar (criterio 1)', () {
    testWidgets('un Runner Experto que no es el autor ve la entrada y la '
        'revisión', (tester) async {
      await abrir(
        tester,
        usuario: luis,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );

      expect(botonRevisar(), findsOneWidget);
      await entrarARevisar(tester);

      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsOneWidget,
      );
      expect(
        find.byKey(RevisarClasificacionScreen.claveConfirmar),
        findsOneWidget,
      );
      expect(base.preguntas, contains((luis, 'ruta-1')));
    });

    testWidgets('quien no es Runner Experto no ve la entrada, y si llega por '
        'un enlace, no puede revisar', (tester) async {
      final router = await abrir(
        tester,
        usuario: marta,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );

      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      expect(botonRevisar(), findsNothing);

      router.push(RevisarClasificacionScreen.rutaDe('ruta-1'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(RevisarClasificacionScreen.claveSinPermiso),
        findsOneWidget,
      );
      expect(
        find.byKey(RevisarClasificacionScreen.claveConfirmar),
        findsNothing,
      );
    });

    testWidgets('un Runner Experto no revisa la clasificación de su propia '
        'ruta', (tester) async {
      final router = await abrir(
        tester,
        usuario: ana,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );

      expect(botonRevisar(), findsNothing);

      router.push(RevisarClasificacionScreen.rutaDe('ruta-1'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(RevisarClasificacionScreen.claveSinPermiso),
        findsOneWidget,
      );
    });

    testWidgets('si la base deja de permitirlo antes de guardar, lo dice y la '
        'ruta queda como estaba', (tester) async {
      await abrir(
        tester,
        usuario: luis,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );
      await entrarARevisar(tester);

      // Mientras miraba los datos, Luis dejó de poder revisar.
      base.expertos.remove(luis);
      await tester.tap(find.byKey(RevisarClasificacionScreen.claveConfirmar));
      await tester.pumpAndSettle();

      expect(find.text(RevisarClasificacionScreen.yaNoPuedes), findsOneWidget);
      expect(base.rutas['ruta-1']!['dificultad_revisada_en'], isNull);
      expect(base.revisiones, isEmpty);
    });
  });

  group('confirmar y corregir dejan la ruta como se espera (criterios 3, 4 '
      'y 5)', () {
    testWidgets('confirmar deja la misma dificultad, revisada por quien '
        'confirmó, y el detalle lo dice', (tester) async {
      await abrir(
        tester,
        usuario: luis,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );
      await entrarARevisar(tester);

      await tester.tap(find.byKey(RevisarClasificacionScreen.claveConfirmar));
      await tester.pumpAndSettle();

      final fila = base.rutas['ruta-1']!;
      expect(fila['dificultad'], 'moderada');
      expect(fila['dificultad_revisada_en'], isNotNull);
      expect(base.revisiones, [('ruta-1', luis, 'confirmar', 'moderada')]);

      // De vuelta en el detalle, ya al día.
      expect(enLaDificultadDelDetalle('Moderada'), findsOneWidget);
      expect(
        enLaDificultadDelDetalle('Revisada por un Runner Experto · Hoy'),
        findsOneWidget,
      );
    });

    testWidgets('corregir deja la dificultad elegida, revisada por quien la '
        'corrigió, y el detalle la muestra', (tester) async {
      await abrir(
        tester,
        usuario: luis,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );
      await entrarARevisar(tester);

      await tester.tap(find.byKey(RevisarClasificacionScreen.claveElegirOtra));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(RevisarClasificacionScreen.claveOpcion(Dificultad.dificil)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RevisarClasificacionScreen.claveGuardar));
      await tester.pumpAndSettle();

      final fila = base.rutas['ruta-1']!;
      expect(fila['dificultad'], 'dificil');
      expect(fila['dificultad_revisada_en'], isNotNull);
      expect(base.revisiones, [('ruta-1', luis, 'corregir', 'dificil')]);

      expect(enLaDificultadDelDetalle('Difícil'), findsOneWidget);
      expect(enLaDificultadDelDetalle('Moderada'), findsNothing);
      expect(
        enLaDificultadDelDetalle('Revisada por un Runner Experto · Hoy'),
        findsOneWidget,
      );
    });

    testWidgets('después, otro usuario ve en el detalle que la revisó un '
        'Runner Experto, sin poder revisarla él', (tester) async {
      await abrir(
        tester,
        usuario: luis,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );
      await entrarARevisar(tester);
      await tester.tap(find.byKey(RevisarClasificacionScreen.claveConfirmar));
      await tester.pumpAndSettle();

      // Marta abre la ruta desde Explorar rutas.
      base.usuario = marta;
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('ruta-1')));
      await tester.pumpAndSettle();

      expect(enLaDificultadDelDetalle('Moderada'), findsOneWidget);
      expect(
        enLaDificultadDelDetalle('Revisada por un Runner Experto · Hoy'),
        findsOneWidget,
      );
      expect(botonRevisar(), findsNothing);
    });

    testWidgets('sin dificultad propuesta no hay nada que confirmar ni '
        'corregir', (tester) async {
      base.rutas['ruta-1']!['dificultad'] = null;
      await abrir(
        tester,
        usuario: luis,
        ubicacion: DetalleRutaScreen.rutaDe('ruta-1'),
      );
      await entrarARevisar(tester);

      expect(
        find.descendant(
          of: find.byKey(RevisarClasificacionScreen.claveDificultad),
          matching: find.text(TarjetaRutaExplorar.sinDificultad),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(RevisarClasificacionScreen.claveConfirmar),
        findsNothing,
      );
      expect(
        find.byKey(RevisarClasificacionScreen.claveElegirOtra),
        findsNothing,
      );
      expect(base.revisiones, isEmpty);
    });
  });
}

/// Una fila de `rutas` como la va a devolver la base cuando exista la
/// dificultad (SCRUM-363), con su trazado.
Map<String, Object?> _fila(
  String id,
  String nombre, {
  required String autorId,
  Dificultad? dificultad,
}) => {
  'id': id,
  'autor_id': autorId,
  'autor_nombre': 'Ana',
  'entrenamiento_id': 'entrenamiento-$id',
  'nombre': nombre,
  'descripcion': null,
  'distancia_km': 7.5,
  'estado': 'publicada',
  'motivo_rechazo': null,
  'fecha_creacion': '2026-10-20T14:00:00Z',
  'fecha_publicacion': '2026-10-20T14:00:00Z',
  'trazado': [
    {'lat': 6.2650, 'lng': -75.5800},
    {'lat': 6.2680, 'lng': -75.5760},
  ],
  'miniatura': [
    {'lat': 6.2650, 'lng': -75.5800},
    {'lat': 6.2680, 'lng': -75.5760},
  ],
  'dificultad': dificultad?.valorDb,
  'dificultad_revisada_en': null,
};

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// La base como la ve la app a través de PostgREST, con el contrato de la
/// revisión (`docs/deudas.md`).
class _BaseFalsa {
  _BaseFalsa({required this.ahora}) {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  late final SupabaseClient cliente;

  /// Cuándo pasa todo, para la fecha de la revisión.
  final DateTime ahora;

  /// Quién tiene la sesión abierta: lo que en la base es `auth.uid()`.
  String? usuario;

  /// Quiénes tienen el rol de Runner Experto (`roles_usuario`).
  final expertos = <String>{};

  /// Las filas de `rutas`, por id.
  final rutas = <String, Map<String, Object?>>{};

  /// Quién preguntó si podía revisar qué ruta.
  final preguntas = <(String?, String)>[];

  /// Cada revisión guardada: la ruta, quién, qué hizo y con qué dificultad.
  final revisiones = <(String, String, String, String)>[];

  /// Lo que no debería haberse pedido.
  final inesperadas = <String>[];

  /// La regla de 0042: Runner Experto y no autor.
  bool _puedeRevisar(String rutaId) {
    final fila = rutas[rutaId];
    return fila != null &&
        expertos.contains(usuario) &&
        fila['autor_id'] != usuario;
  }

  Future<http.Response> _responder(http.Request peticion) async {
    final url = peticion.url;
    final post = peticion.method == 'POST';
    final parametros = post && peticion.body.isNotEmpty
        ? jsonDecode(peticion.body) as Map<String, Object?>
        : const <String, Object?>{};
    final rutaId = parametros['p_ruta_id'] as String?;

    if (post && url.path == '/rest/v1/rpc/rutas_cercanas') {
      return _json([
        for (final fila in rutas.values)
          if (fila['estado'] == 'publicada')
            {...fila, 'distancia_usuario_km': 1.2},
      ], peticion);
    }

    if (post && url.path == '/rest/v1/rpc/puede_revisar_clasificacion') {
      preguntas.add((usuario, rutaId!));
      return _json(_puedeRevisar(rutaId), peticion);
    }

    if (post &&
        (url.path == '/rest/v1/rpc/confirmar_clasificacion' ||
            url.path == '/rest/v1/rpc/corregir_clasificacion')) {
      if (!_puedeRevisar(rutaId!)) {
        return _error('42501', 'no puede revisar esta ruta', 403, peticion);
      }
      final fila = rutas[rutaId]!;
      final corregir = url.path.endsWith('corregir_clasificacion');
      final dificultad = corregir
          ? parametros['p_dificultad'] as String?
          : fila['dificultad'] as String?;
      if (dificultad == null ||
          Dificultad.values.every((d) => d.valorDb != dificultad)) {
        return _error('22023', 'no hay una dificultad válida', 400, peticion);
      }
      fila
        ..['dificultad'] = dificultad
        ..['dificultad_revisada_en'] = ahora.toIso8601String();
      revisiones.add((
        rutaId,
        usuario!,
        corregir ? 'corregir' : 'confirmar',
        dificultad,
      ));
      return http.Response('', 204, request: peticion);
    }

    if (peticion.method == 'GET' && url.path == '/rest/v1/rutas') {
      final id = url.queryParameters['id']?.replaceFirst('eq.', '');
      // `maybeSingle` en un GET espera una lista: vacía si no hay fila.
      return _json([?rutas[id]], peticion);
    }

    inesperadas.add('${peticion.method} $url');
    return http.Response('', 404, request: peticion);
  }

  static http.Response _json(Object? cuerpo, http.Request peticion) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(cuerpo)),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
        request: peticion,
      );

  static http.Response _error(
    String codigo,
    String mensaje,
    int estado,
    http.Request peticion,
  ) => http.Response(
    jsonEncode({'code': codigo, 'message': mensaje}),
    estado,
    headers: const {'content-type': 'application/json'},
    request: peticion,
  );

  Future<void> cerrar() => cliente.dispose();
}
