// Pruebas de integración de buscar rutas por ubicación (HU-30, SCRUM-258):
// los tres tipos de búsqueda —por nombre, por zona y por creador—, el caso
// sin resultados y el regreso a las rutas cercanas al limpiar.
//
// Monta la sección de Rutas tal como la registra la app (`seccionRutas`),
// con el repositorio de verdad y el buscador de zonas de verdad. Solo se
// reemplaza lo que sale a la red o al teléfono: Supabase y Nominatim
// contestan desde clientes HTTP falsos, y la ubicación y los permisos salen
// de fuentes falsas. Las respuestas de Nominatim están copiadas de
// consultas reales del 2026-10-23.
//
// Lo que estas pruebas NO prueban:
// - Cómo compara la base. Lo hacen `buscar_rutas` (0040) y su ajuste por
//   comienzo de palabra (0041), que no se pueden ejecutar desde aquí; sus
//   comprobaciones están escritas al final de cada migración. Lo que se
//   comprueba es qué le pregunta la app y qué hace con lo que vuelve.
// - Nominatim de verdad, que no se consulta desde una prueba: su política
//   de uso no lo permitiría con cada corrida.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/busqueda_rutas_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/services/zonas_service.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 18, 12);

  // Cuatro rutas de la comunidad, de cuatro personas. La del Escobero
  // arranca en Envigado y no lo dice en su nombre: solo la encuentra la
  // búsqueda por zona.
  final nutibara = _fila(
    'r-nutibara',
    'Subida al Nutibara',
    autor: 'Ana',
    publicada: DateTime.utc(2026, 10, 10, 14),
  );
  final parque = _fila(
    'r-parque',
    'Vuelta al Parque Norte',
    autor: 'Luis Pérez',
    publicada: DateTime.utc(2026, 10, 17, 14),
  );
  final escobero = _fila(
    'r-escobero',
    'Loma del Escobero',
    autor: 'Marta',
    publicada: DateTime.utc(2026, 10, 12, 14),
  );
  final rio = _fila(
    'r-rio',
    'Ciclovía del río',
    autor: 'Mariana Ríos',
    publicada: DateTime.utc(2026, 10, 18, 14),
  );

  // El usuario, en la Universidad de Medellín.
  final enLaU = puntoDePrueba(latitud: 6.2318, longitud: -75.6105);

  late _BaseFalsa base;
  late _NominatimFalso nominatim;
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    base = _BaseFalsa()
      ..cercanas = [
        {...nutibara, 'distancia_usuario_km': 2.1},
        {...rio, 'distancia_usuario_km': 3.4},
        {...parque, 'distancia_usuario_km': 7.8},
        {...escobero, 'distancia_usuario_km': 9.6},
      ];

    nominatim = _NominatimFalso({
      // Cerca del usuario, el límite real del municipio.
      ('envigado', cerca: true): [_envigadoComoNominatim],
      // "Luis" no es nada cerca; en todo el país, una tienda y una casa.
      ('luis', cerca: true): const [],
      ('luis', cerca: false): _luisComoNominatim,
    });

    permisos = _MockPermisosService();
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);

    fuente = FuenteUbicacionFalsa()..puntoActual = enLaU;
  });

  tearDown(() => fuente.cerrar());

  /// Abre la app en la portada y entra a Rutas desde la barra de abajo.
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
          buscadorDeZonasProvider.overrideWithValue(
            NominatimBuscadorDeZonas(
              cliente: MockClient(nominatim.responder),
              enNavegador: false,
              intervaloMinimo: Duration.zero,
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

  /// Escribe en la barra y deja pasar la espera y la consulta.
  Future<void> escribir(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
    await tester.pump(esperaBusquedaRutas);
    await tester.pumpAndSettle();
  }

  /// La tecla de buscar, o Enter en el navegador.
  Future<void> confirmar(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  List<String> enPantalla(WidgetTester tester) => [
    for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
      find.byType(TarjetaRutaExplorar),
    ))
      tarjeta.ruta.nombre,
  ];

  group('criterio 1: buscar por texto', () {
    testWidgets('al escribir, le pregunta a la base por lo escrito, desde '
        'donde está el usuario, y muestra lo que vuelve en la misma lista y '
        'con la misma tarjeta', (tester) async {
      base.alBuscar = (_) => [
        {...nutibara, 'distancia_usuario_km': 2.1},
      ];
      await abrirRutas(tester);

      await escribir(tester, 'nutibara');

      expect(base.busquedas, [
        {
          'p_termino': 'nutibara',
          'p_latitud': enLaU.latitud,
          'p_longitud': enLaU.longitud,
          'p_limite': SupabaseRutasRepository.limite,
        },
      ]);
      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(enPantalla(tester), ['Subida al Nutibara']);
      expect(
        tester
            .widget<TarjetaRutaExplorar>(find.byType(TarjetaRutaExplorar))
            .compacta,
        isFalse,
      );
      // Mientras se escribe no se le pregunta a Nominatim: su política no
      // admite una consulta por letra.
      expect(nominatim.peticiones, isEmpty);
    });

    testWidgets('espera a que el usuario deje de escribir: sale una sola '
        'consulta', (tester) async {
      await abrirRutas(tester);

      for (final texto in ['nu', 'nuti', 'nutibara']) {
        await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect([for (final b in base.busquedas) b['p_termino']], ['nutibara']);
    });
  });

  group('criterio 2: buscar por zona', () {
    testWidgets('al confirmar un lugar, se lo pregunta a Nominatim cerca del '
        'usuario y busca también las rutas que arrancan ahí, aunque estén '
        'lejos', (tester) async {
      base.alBuscar = (parametros) => [
        if (parametros.containsKey('p_zona_sur'))
          {...escobero, 'distancia_usuario_km': 9.6},
      ];
      await abrirRutas(tester);

      await escribir(tester, 'envigado');
      expect(nominatim.peticiones, isEmpty);
      await confirmar(tester);

      // Nominatim: lo escrito, alrededor del usuario y con la app
      // identificada.
      final pregunta = nominatim.peticiones.single;
      expect(pregunta.url.queryParameters['q'], 'envigado');
      expect(
        pregunta.url.queryParameters['viewbox'],
        '-75.80,6.40,-75.40,6.00',
      );
      expect(pregunta.url.queryParameters['bounded'], '1');
      expect(pregunta.headers['User-Agent'], NominatimBuscadorDeZonas.agente);

      // La base: lo escrito y la caja real de Envigado.
      final busqueda = base.busquedas.last;
      expect(busqueda['p_termino'], 'envigado');
      expect(busqueda['p_zona_sur'], 6.1003036);
      expect(busqueda['p_zona_oeste'], -75.6049283);
      expect(busqueda['p_zona_norte'], 6.1983821);
      expect(busqueda['p_zona_este'], -75.4741457);

      expect(enPantalla(tester), ['Loma del Escobero']);
      expect(
        find.textContaining('Envigado, Antioquia', findRichText: true),
        findsOneWidget,
      );
      expect(find.text(RutasScreen.atribucionZonas), findsOneWidget);
    });
  });

  group('criterio 3: buscar por creador', () {
    testWidgets('con el nombre de quien la publicó salen sus rutas; al '
        'confirmar, la tienda "Luis" que trae Nominatim no se toma por zona', (
      tester,
    ) async {
      base.alBuscar = (_) => [
        {...parque, 'distancia_usuario_km': 7.8},
      ];
      await abrirRutas(tester);

      await escribir(tester, 'luis');
      expect(enPantalla(tester), ['Vuelta al Parque Norte']);

      await confirmar(tester);

      // Preguntó cerca y en todo el país, y nada de eso era un lugar.
      expect(nominatim.peticiones, hasLength(2));
      expect(base.busquedas.last.containsKey('p_zona_sur'), isFalse);
      expect(enPantalla(tester), ['Vuelta al Parque Norte']);
      expect(find.byKey(RutasScreen.claveNotaZona), findsNothing);
    });
  });

  group('criterio 4: sin resultados', () {
    testWidgets('si la base no devuelve nada, lo dice y sugiere revisar lo '
        'escrito', (tester) async {
      await abrirRutas(tester);

      await escribir(tester, 'zzz');

      expect(base.busquedas.single['p_termino'], 'zzz');
      expect(find.text(RutasScreen.sinResultados), findsOneWidget);
      expect(find.textContaining('«zzz»'), findsOneWidget);
      expect(find.textContaining(RutasScreen.revisaLoEscrito), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
    });
  });

  group('criterio 5: limpiar la búsqueda', () {
    testWidgets('al borrarla vuelven las rutas cercanas, en su orden y sin '
        'volver a consultarlas', (tester) async {
      base.alBuscar = (_) => [
        {...nutibara, 'distancia_usuario_km': 2.1},
      ];
      await abrirRutas(tester);
      expect(base.consultasCercanas, 1);
      await escribir(tester, 'nutibara');

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), '');
      await tester.pump();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(find.text(RutasScreen.rotuloResultados), findsNothing);
      expect(enPantalla(tester), [
        'Subida al Nutibara',
        'Ciclovía del río',
        'Vuelta al Parque Norte',
        'Loma del Escobero',
      ]);
      expect(base.consultasCercanas, 1);
    });

    testWidgets('también después de buscar por zona: el lugar se olvida', (
      tester,
    ) async {
      base.alBuscar = (_) => [
        {...escobero, 'distancia_usuario_km': 9.6},
      ];
      await abrirRutas(tester);
      await escribir(tester, 'envigado');
      await confirmar(tester);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), '');
      await tester.pump();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(find.byKey(RutasScreen.claveNotaZona), findsNothing);

      // Al volver a escribir lo mismo, sin confirmar, no busca en el lugar.
      await escribir(tester, 'envigado');
      expect(base.busquedas.last.containsKey('p_zona_sur'), isFalse);
    });
  });
}

/// Una fila de `rutas` como la devuelven las consultas de la base: sin el
/// trazado y con la miniatura.
Map<String, Object?> _fila(
  String id,
  String nombre, {
  required String autor,
  required DateTime publicada,
}) => {
  'id': id,
  'autor_id': 'autor-$id',
  'autor_nombre': autor,
  'entrenamiento_id': 'entrenamiento-$id',
  'nombre': nombre,
  'descripcion': null,
  'distancia_km': 5.23,
  'estado': 'publicada',
  'motivo_rechazo': null,
  'fecha_creacion': publicada.toIso8601String(),
  'fecha_publicacion': publicada.toIso8601String(),
  'miniatura': [
    {'lat': 6.2442, 'lng': -75.5812},
    {'lat': 6.2444, 'lng': -75.5802},
  ],
};

/// Envigado como lo devolvió Nominatim cerca de Medellín.
const _envigadoComoNominatim = {
  'name': 'Envigado',
  'display_name':
      'Envigado, Valle de Aburrá, Antioquia, RAP del Agua y la Montaña, '
      'Colombia',
  'category': 'boundary',
  'type': 'administrative',
  'place_rank': 12,
  'boundingbox': ['6.1003036', '6.1983821', '-75.6049283', '-75.4741457'],
  'address': {
    'town': 'Envigado',
    'state_district': 'Valle de Aburrá',
    'state': 'Antioquia',
    'country': 'Colombia',
  },
};

/// "Luis" en todo el país, como lo devolvió Nominatim: una tienda y una
/// casa.
const _luisComoNominatim = [
  {
    'name': 'Luis',
    'category': 'shop',
    'type': 'supermarket',
    'place_rank': 30,
    'boundingbox': ['4.6100', '4.6102', '-74.0820', '-74.0818'],
    'address': {'state': 'Bogotá, Distrito Capital'},
  },
  {
    'name': 'Luis',
    'category': 'building',
    'type': 'yes',
    'place_rank': 30,
    'boundingbox': ['4.4300', '4.4302', '-75.2400', '-75.2398'],
    'address': {'state': 'Tolima'},
  },
];

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// La base como la ve la app a través de PostgREST: `rutas_cercanas` y
/// `buscar_rutas`. Contesta lo que la prueba le indique y anota lo que se le
/// pidió.
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

  /// Lo que devuelve `rutas_cercanas`, ya de la más cercana a la más lejana.
  List<Map<String, Object?>> cercanas = const [];
  int consultasCercanas = 0;

  /// Lo que devuelve `buscar_rutas` según lo que se le pidió. La base es la
  /// que decide qué coincide; aquí lo decide la prueba.
  List<Map<String, Object?>> Function(Map<String, Object?> parametros)
  alBuscar = (_) => const [];

  /// Los parámetros de cada llamada a `buscar_rutas`.
  final busquedas = <Map<String, Object?>>[];

  /// Lo que no debería haberse pedido.
  final inesperadas = <String>[];

  Future<http.Response> _responder(http.Request peticion) async {
    final url = peticion.url;
    if (peticion.method == 'POST' &&
        url.path == '/rest/v1/rpc/rutas_cercanas') {
      consultasCercanas++;
      return _json(cercanas, peticion);
    }
    if (peticion.method == 'POST' && url.path == '/rest/v1/rpc/buscar_rutas') {
      final parametros = jsonDecode(peticion.body) as Map<String, Object?>;
      busquedas.add(parametros);
      return _json(alBuscar(parametros), peticion);
    }

    inesperadas.add('${peticion.method} $url');
    return http.Response('', 404, request: peticion);
  }

  static http.Response _json(Object cuerpo, http.Request peticion) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(cuerpo)),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
        request: peticion,
      );

  Future<void> cerrar() => cliente.dispose();
}

/// Nominatim de mentira: contesta por lo escrito y por si se preguntó solo
/// cerca del usuario, y anota cada pregunta.
class _NominatimFalso {
  _NominatimFalso(this.lugares);

  final Map<(String, {bool cerca}), List<Map<String, Object?>>> lugares;

  final peticiones = <http.Request>[];

  Future<http.Response> responder(http.Request peticion) async {
    peticiones.add(peticion);
    final parametros = peticion.url.queryParameters;
    final escrito = (parametros['q'] ?? '').toLowerCase();
    final cerca = parametros['bounded'] == '1';

    return http.Response.bytes(
      utf8.encode(jsonEncode(lugares[(escrito, cerca: cerca)] ?? const [])),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: peticion,
    );
  }
}
