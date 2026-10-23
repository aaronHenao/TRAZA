// Pruebas de integración de buscar rutas cercanas (HU-29, SCRUM-251): sus
// cinco criterios de aceptación, de la ubicación del usuario a la consulta,
// de la consulta a la lista y de la lista al detalle.
//
// Monta la sección de Rutas tal como la registra la app (`seccionRutas`) y el
// repositorio de verdad. Solo se reemplaza lo que necesita red o teléfono:
// Supabase contesta desde un cliente HTTP falso, como contestaría PostgREST,
// y la ubicación y los permisos salen de fuentes falsas.
//
// Lo que estas pruebas NO prueban:
// - El orden en sí. Lo calcula la base en `rutas_cercanas` (0037) y no se
//   puede ejecutar desde aquí; su comprobación está escrita al final de esa
//   migración. Lo que se comprueba es que la app le pregunta desde donde está
//   el usuario y muestra lo que la base devuelve en ese orden, sin
//   reordenarlo.
// - El GPS y la ventana del permiso de verdad. `UbicacionGeolocator` es una
//   capa delgada sobre el plugin y se revisa en el teléfono.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/explorar_rutas_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/aviso_permiso_ubicacion.dart';
import 'package:traza/widgets/mapa_trayecto.dart';
import 'package:traza/widgets/miniatura_ruta.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 18, 12);

  // Tres rutas de la comunidad. De cerca a lejos van cerro, parque y río; de
  // la más reciente a la más antigua, al revés. Así se nota cuál de los dos
  // órdenes manda en cada caso.
  final cerro = _fila(
    'r-cerro',
    'Subida al Nutibara',
    autor: 'Ana',
    distanciaKm: 4.1,
    publicada: DateTime.utc(2026, 10, 10, 14),
  );
  final parque = _fila(
    'r-parque',
    'Vuelta al Parque Norte',
    autor: 'Luis',
    distanciaKm: 5.23,
    publicada: DateTime.utc(2026, 10, 17, 14),
  );
  final rio = _fila(
    'r-rio',
    'Ciclovía del río',
    autor: 'Marta',
    distanciaKm: null,
    publicada: DateTime.utc(2026, 10, 18, 14),
  );

  // El usuario, en la Universidad de Medellín.
  final enLaU = puntoDePrueba(latitud: 6.2318, longitud: -75.6105);

  late _BaseFalsa base;
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    base = _BaseFalsa()
      ..cercanas = [
        {...cerro, 'distancia_usuario_km': 0.8},
        {...parque, 'distancia_usuario_km': 2.5},
        {...rio, 'distancia_usuario_km': 7.1},
      ]
      ..publicadas = [rio, parque, cerro]
      ..completas = {
        for (final fila in [cerro, parque, rio])
          fila['id']! as String: {...fila, 'trazado': _comoJson(_recorrido)},
      };

    permisos = _MockPermisosService();
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});

    fuente = FuenteUbicacionFalsa()..puntoActual = enLaU;
  });

  tearDown(() => fuente.cerrar());

  /// Abre la app en la portada y entra a Rutas desde la barra de abajo, como
  /// lo hace el usuario.
  Future<void> abrirRutas(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(base.cerrar);
    addTearDown(() => expect(base.inesperadas, isEmpty));

    final router = GoRouter(
      initialLocation: SeccionPrincipal.inicio.ruta,
      routes: [
        seccionRutas,
        // Las demás secciones, de mentira, con la barra de verdad.
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
              usuarioActual: () => 'usuario-1',
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

    await tester.tap(find.text(SeccionPrincipal.rutas.etiqueta));
    await tester.pumpAndSettle();
  }

  /// Los nombres de las rutas en el orden en que se ven, de arriba abajo.
  List<String> enPantalla(WidgetTester tester) {
    final nombres = [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.nombre,
    ];
    double alto(String nombre) => tester.getTopLeft(find.text(nombre)).dy;
    return nombres..sort((a, b) => alto(a).compareTo(alto(b)));
  }

  group('criterio 1: rutas ordenadas por cercanía', () {
    testWidgets('con el permiso, pide las rutas desde donde está el usuario y '
        'las muestra de la más cercana a la más lejana', (tester) async {
      await abrirRutas(tester);

      expect(base.consultasCercanas, [
        {
          'p_latitud': enLaU.latitud,
          'p_longitud': enLaU.longitud,
          'p_radio_km': radioRutasCercanasKm,
          'p_limite': SupabaseRutasRepository.limite,
        },
      ]);
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      // El orden de la base, aunque la más cercana sea la más antigua.
      expect(enPantalla(tester), [
        'Subida al Nutibara',
        'Vuelta al Parque Norte',
        'Ciclovía del río',
      ]);
      // Sabiendo dónde está, no hace falta la lista por fecha.
      expect(base.consultasPublicadas, 0);
    });

    testWidgets('si el usuario se movió, al deslizar hacia abajo vuelve a '
        'preguntar desde donde está ahora', (tester) async {
      await abrirRutas(tester);

      // Ahora está en el Parque Norte, donde el río queda más cerca.
      final enElParque = puntoDePrueba(latitud: 6.2700, longitud: -75.5690);
      fuente.puntoActual = enElParque;
      base.cercanas = [
        {...rio, 'distancia_usuario_km': 0.4},
        {...parque, 'distancia_usuario_km': 1.1},
        {...cerro, 'distancia_usuario_km': 6.0},
      ];

      await tester.fling(
        find.byKey(RutasScreen.claveLista),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(base.consultasCercanas, hasLength(2));
      expect(base.consultasCercanas.last['p_latitud'], enElParque.latitud);
      expect(base.consultasCercanas.last['p_longitud'], enElParque.longitud);
      expect(enPantalla(tester), [
        'Ciclovía del río',
        'Vuelta al Parque Norte',
        'Subida al Nutibara',
      ]);
    });
  });

  group('criterio 2: la información de cada ruta', () {
    testWidgets('dice su nombre, su dificultad, su distancia total, su '
        'desnivel y quién la creó', (tester) async {
      await abrirRutas(tester);

      final tarjeta = find.byKey(TarjetaRutaExplorar.claveDe('r-parque'));
      Finder en(Finder buscado) =>
          find.descendant(of: tarjeta, matching: buscado);

      expect(en(find.text('Vuelta al Parque Norte')), findsOneWidget);
      expect(en(find.text('Por Luis')), findsOneWidget);
      expect(en(find.text('5.23 km')), findsOneWidget);
      // La dificultad la asigna HU-34 y el desnivel necesita la altitud, que
      // no se guarda: hasta entonces se dice, no se inventa.
      expect(en(find.text(TarjetaRutaExplorar.sinDificultad)), findsOneWidget);
      expect(en(find.text(TarjetaRutaExplorar.sinDesnivel)), findsOneWidget);
      // Y la forma del recorrido, con la miniatura que manda la base.
      expect(
        tester.widget<MiniaturaRuta>(en(find.byType(MiniaturaRuta))).puntos,
        [_recorrido.first, _recorrido.last],
      );
    });

    testWidgets('una ruta guardada sin su distancia lo dice en vez de '
        'inventarla', (tester) async {
      await abrirRutas(tester);

      final tarjeta = find.byKey(TarjetaRutaExplorar.claveDe('r-rio'));
      expect(
        find.descendant(
          of: tarjeta,
          matching: find.text(TarjetaRuta.sinDistancia),
        ),
        findsOneWidget,
      );
    });
  });

  group('criterio 3: el permiso de ubicación', () {
    testWidgets('sin él, explica por qué lo necesita y ofrece concederlo; '
        'mientras, muestra las más recientes', (tester) async {
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);

      await abrirRutas(tester);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsOneWidget);
      expect(find.text(AvisoPermisoUbicacion.porQue), findsOneWidget);
      expect(find.byKey(AvisoPermisoUbicacion.claveBoton), findsOneWidget);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
      expect(enPantalla(tester), [
        'Ciclovía del río',
        'Vuelta al Parque Norte',
        'Subida al Nutibara',
      ]);
      // Se las pidió a la base por fecha, y al GPS no le preguntó nada.
      expect(base.ordenDePublicadas, startsWith('fecha_publicacion.desc'));
      expect(base.consultasCercanas, isEmpty);
      expect(fuente.lecturasPuntuales, 0);
    });

    testWidgets('al concederlo, la lista pasa a ir por cercanía sin hacer '
        'nada más', (tester) async {
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await abrirRutas(tester);

      await tester.tap(find.byKey(AvisoPermisoUbicacion.claveBoton));
      await tester.pumpAndSettle();

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(base.consultasCercanas.single['p_latitud'], enLaU.latitud);
      expect(enPantalla(tester).first, 'Subida al Nutibara');
    });

    testWidgets('si lo negó para siempre, lo manda a los ajustes y al volver '
        'con el permiso la lista va por cercanía', (tester) async {
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.bloqueado);
      await abrirRutas(tester);

      await tester.tap(find.byKey(AvisoPermisoUbicacion.claveBoton));
      await tester.pumpAndSettle();
      verify(() => permisos.abrirAjustes()).called(1);

      // Allá lo concedió, y vuelve a la app.
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      for (final estado in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(estado);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(base.consultasCercanas, hasLength(1));
    });

    testWidgets('con el permiso pero la ubicación del teléfono apagada, no '
        'pide el permiso otra vez: pide encenderla', (tester) async {
      fuente.servicio = false;

      await abrirRutas(tester);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      expect(find.text(RutasScreen.ubicacionApagada), findsOneWidget);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
      expect(base.consultasCercanas, isEmpty);
    });
  });

  group('criterio 4: sin rutas cerca', () {
    testWidgets('lo dice en lugar de mostrar una lista vacía', (tester) async {
      base.cercanas = const [];

      await abrirRutas(tester);

      expect(find.byKey(RutasScreen.claveSinRutasCerca), findsOneWidget);
      expect(find.text(RutasScreen.sinRutasCerca), findsOneWidget);
      expect(
        find.textContaining('${radioRutasCercanasKm.round()} km'),
        findsOneWidget,
      );
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
      // No rellena con rutas lejanas por fecha: diría que están cerca.
      expect(base.consultasPublicadas, 0);
    });

    testWidgets('sin ninguna publicada en toda la comunidad dice eso otro', (
      tester,
    ) async {
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      base.publicadas = const [];

      await abrirRutas(tester);

      expect(find.byKey(RutasScreen.claveSinRutas), findsOneWidget);
      expect(find.byKey(RutasScreen.claveSinRutasCerca), findsNothing);
    });

    testWidgets('si la consulta no llega a la base, no lo confunde con que no '
        'haya rutas, y "Reintentar" las trae', (tester) async {
      base.sinRed = true;

      await abrirRutas(tester);

      expect(find.byKey(RutasScreen.claveError), findsOneWidget);
      expect(find.text(RutasScreen.errorDeConexion), findsOneWidget);
      expect(find.byKey(RutasScreen.claveSinRutasCerca), findsNothing);

      base.sinRed = false;
      await tester.tap(find.byKey(RutasScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.byKey(RutasScreen.claveError), findsNothing);
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(3));
    });
  });

  group('criterio 5: abrir el detalle', () {
    testWidgets('al tocar una ruta abre el detalle de esa ruta, con su '
        'recorrido completo, y "atrás" vuelve a la lista', (tester) async {
      await abrirRutas(tester);

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-parque')));
      await tester.pumpAndSettle();

      // La pidió por su id, esta vez con el trazado.
      expect(base.detallesPedidos, ['r-parque']);
      expect(base.columnasDelDetalle, contains('trazado'));

      expect(find.byType(DetalleRutaScreen), findsOneWidget);
      expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
      expect(find.text('5.23 km'), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        [for (final punto in _recorrido) LatLng(punto.latitud, punto.longitud)],
      );

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsNothing);
      expect(enPantalla(tester).first, 'Subida al Nutibara');
      // La lista seguía ahí: no se volvió a consultar.
      expect(base.consultasCercanas, hasLength(1));
    });

    testWidgets('si la ruta dejó de estar publicada mientras la miraba en la '
        'lista, el detalle lo dice', (tester) async {
      // RLS ya no la deja leer: la base contesta sin filas.
      base.completas = {...base.completas}..remove('r-rio');

      await abrirRutas(tester);
      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-rio')));
      await tester.pumpAndSettle();

      expect(find.text('Esta ruta ya no está disponible'), findsOneWidget);
      expect(find.byType(MapaTrayecto), findsNothing);
    });
  });
}

/// Un recorrido corto por el centro de Medellín.
const _recorrido = [
  PuntoRuta(latitud: 6.2442, longitud: -75.5812),
  PuntoRuta(latitud: 6.2445, longitud: -75.5808),
  PuntoRuta(latitud: 6.2448, longitud: -75.5809),
  PuntoRuta(latitud: 6.2447, longitud: -75.5804),
  PuntoRuta(latitud: 6.2444, longitud: -75.5802),
];

List<Map<String, double>> _comoJson(List<PuntoRuta> puntos) => [
  for (final punto in puntos) {'lat': punto.latitud, 'lng': punto.longitud},
];

/// Una fila de `rutas` como la devuelve PostgREST en un listado: sin el
/// trazado y con la miniatura (0038), que aquí es solo el inicio y el final.
Map<String, Object?> _fila(
  String id,
  String nombre, {
  required String autor,
  required double? distanciaKm,
  required DateTime publicada,
}) => {
  'id': id,
  'autor_id': 'autor-$id',
  'autor_nombre': autor,
  'entrenamiento_id': 'entrenamiento-$id',
  'nombre': nombre,
  'descripcion': null,
  'distancia_km': distanciaKm,
  'estado': 'publicada',
  'motivo_rechazo': null,
  'fecha_creacion': publicada.toIso8601String(),
  'fecha_publicacion': publicada.toIso8601String(),
  'miniatura': _comoJson([_recorrido.first, _recorrido.last]),
};

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// La base como la ve la app a través de PostgREST: la función
/// `rutas_cercanas` y la tabla `rutas`. Contesta lo que la prueba le indique
/// y anota lo que se le pidió.
class _BaseFalsa {
  _BaseFalsa() {
    cliente = SupabaseClient(
      'https://proyecto-de-prueba.supabase.co',
      'clave-de-prueba',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_responder),
    );
  }

  late final SupabaseClient cliente;

  /// Lo que devuelve `rutas_cercanas`, ya en el orden en que lo daría la
  /// base: de la más cercana a la más lejana.
  List<Map<String, Object?>> cercanas = const [];

  /// Las publicadas, para cuando no se sabe dónde está el usuario.
  List<Map<String, Object?>> publicadas = const [];

  /// Cada ruta con su trazado, por id, como la lee el detalle.
  Map<String, Map<String, Object?>> completas = const {};

  /// La petición a `rutas_cercanas` no llega: no hay conexión.
  bool sinRed = false;

  /// Los parámetros de cada llamada a `rutas_cercanas`.
  final consultasCercanas = <Map<String, Object?>>[];

  int consultasPublicadas = 0;
  String? ordenDePublicadas;

  /// Los ids que pidió el detalle, y las columnas de la última vez.
  final detallesPedidos = <String>[];
  String? columnasDelDetalle;

  /// Lo que no debería haberse pedido.
  final inesperadas = <String>[];

  Future<http.Response> _responder(http.Request peticion) async {
    final url = peticion.url;

    if (peticion.method == 'POST' &&
        url.path == '/rest/v1/rpc/rutas_cercanas') {
      consultasCercanas.add(jsonDecode(peticion.body) as Map<String, Object?>);
      if (sinRed) throw http.ClientException('Sin conexión', url);
      return _json(cercanas, peticion);
    }

    if (peticion.method == 'GET' && url.path == '/rest/v1/rutas') {
      final filtroId = url.queryParameters['id'];
      if (filtroId != null) {
        // `maybeSingle` en un GET espera una lista: vacía si no hay fila.
        final id = filtroId.replaceFirst('eq.', '');
        detallesPedidos.add(id);
        columnasDelDetalle = url.queryParameters['select'];
        return _json([?completas[id]], peticion);
      }
      if (url.queryParameters['estado'] == 'eq.publicada') {
        consultasPublicadas++;
        ordenDePublicadas = url.queryParameters['order'];
        return _json(publicadas, peticion);
      }
    }

    inesperadas.add('${peticion.method} $url');
    return http.Response('', 404, request: peticion);
  }

  static http.Response _json(Object cuerpo, http.Request peticion) =>
      http.Response(
        jsonEncode(cuerpo),
        200,
        headers: const {'content-type': 'application/json'},
        request: peticion,
      );

  Future<void> cerrar() => cliente.dispose();
}
