// Pruebas de integración de filtrar rutas por distancia (HU-37, SCRUM-276):
// cada rango, la combinación con la dificultad y el retiro del filtro.
//
// Monta la sección de Rutas tal como la registra la app (`seccionRutas`),
// con el repositorio de verdad. Solo se reemplaza lo que necesita red o
// teléfono: Supabase contesta desde un cliente HTTP falso, como contestaría
// PostgREST, y la ubicación y los permisos salen de fuentes falsas. Así se
// prueba el camino entero, de la fila de la base a la tarjeta, incluida una
// distancia que llega como texto.
//
// Lo que estas pruebas NO prueban:
// - La dificultad que guarda la base. `rutas.dificultad` todavía no existe
//   (la crea SCRUM-363): las filas de aquí la traen como la traerá, con los
//   valores de `Dificultad.valorDb`, salvo en la prueba que muestra lo que
//   pasa hoy. Y como la dificultad todavía no tiene chips (SCRUM-266), se
//   elige como lo harán ellos.
// - Un filtro en la base: no lo hay. Se filtra en la app sobre las rutas que
//   ya llegaron, y lo que se comprueba es justamente que cambiar de filtro
//   no vuelve a consultar.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/busqueda_rutas_provider.dart';
import 'package:traza/services/filtros_rutas_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/services/zonas_service.dart';
import 'package:traza/widgets/chip_filtro.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/buscador_de_zonas_falso.dart';
import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 18, 12);

  // Nueve rutas de la comunidad, de la más cercana a la más lejana. Hay al
  // menos una en cada rango, y las de los bordes: 5, 10 y 20 km justos, una
  // de 4,996 km que la tarjeta muestra como "5 km", una cuya distancia llega
  // como texto y una sin distancia registrada.
  final parque = _fila(
    'r-parque',
    'Vuelta al parque',
    autor: 'Ana Gómez',
    distancia: 3.2,
    dificultad: Dificultad.facil,
  );
  final santaElena = _fila(
    'r-santa-elena',
    'Subida a Santa Elena',
    autor: 'Luis Pérez',
    distancia: 15,
    dificultad: Dificultad.facil,
  );
  final balsos = _fila(
    'r-balsos',
    'Loma de los Balsos',
    autor: 'Ana Gómez',
    distancia: 5,
    dificultad: Dificultad.moderada,
  );
  final rio = _fila(
    'r-rio',
    'Casi cinco por el río',
    autor: 'Marta',
    distancia: 4.996,
    dificultad: Dificultad.facil,
  );
  final estadio = _fila(
    'r-estadio',
    'Circuito del estadio',
    autor: 'Luis Pérez',
    distancia: 10,
    dificultad: Dificultad.dificil,
  );
  final volador = _fila(
    'r-volador',
    'Cerro Volador',
    autor: 'Marta',
    // `numeric` llega como número o como texto, según el caso.
    distancia: '7.50',
    dificultad: Dificultad.moderada,
  );
  final guatape = _fila(
    'r-guatape',
    'Travesía a Guatapé',
    autor: 'Ana Gómez',
    distancia: 20,
    dificultad: Dificultad.moderada,
  );
  final oriente = _fila(
    'r-oriente',
    'Ultra del Oriente',
    autor: 'Luis Pérez',
    distancia: 42.2,
    dificultad: Dificultad.dificil,
  );
  final sinMedir = _fila(
    'r-sin-medir',
    'Paseo sin medir',
    autor: 'Marta',
    distancia: null,
  );
  final todas = [
    parque,
    santaElena,
    balsos,
    rio,
    estadio,
    volador,
    guatape,
    oriente,
    sinMedir,
  ];
  final nombres = [for (final fila in todas) fila['nombre']! as String];

  late _BaseFalsa base;
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    base = _BaseFalsa()
      ..cercanas = [
        for (final (i, fila) in todas.indexed)
          {...fila, 'distancia_usuario_km': 0.4 + i * 0.7},
      ]
      ..publicadas = todas;

    permisos = _MockPermisosService();
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});

    // El usuario, en la Universidad de Medellín.
    fuente = FuenteUbicacionFalsa()
      ..puntoActual = puntoDePrueba(latitud: 6.2318, longitud: -75.6105);
  });

  tearDown(() => fuente.cerrar());

  /// Abre la app en la portada y entra a Rutas desde la barra de abajo, como
  /// lo hace el usuario.
  Future<void> abrirRutas(WidgetTester tester) async {
    // Alta para que la lista construya todas las tarjetas: las que quedan
    // fuera de la pantalla no se construyen, y no se podrían contar.
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
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
          // Buscar sin confirmar no le pregunta a nadie por lugares, pero por
          // si acaso, nada sale a Nominatim.
          buscadorDeZonasProvider.overrideWithValue(BuscadorDeZonasFalso()),
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
    final vistas = [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.nombre,
    ];
    double alto(String nombre) => tester.getTopLeft(find.text(nombre)).dy;
    return vistas..sort((a, b) => alto(a).compareTo(alto(b)));
  }

  /// Toca el chip del rango, como el usuario: si ya estaba elegido, lo quita.
  Future<void> tocarRango(WidgetTester tester, RangoDistancia rango) async {
    await tester.tap(find.byKey(RutasScreen.claveRango(rango)));
    await tester.pumpAndSettle();
  }

  /// Elige una dificultad como lo harán los chips de SCRUM-266. Null es
  /// "Todas".
  Future<void> elegirDificultad(
    WidgetTester tester,
    Dificultad? dificultad,
  ) async {
    ProviderScope.containerOf(
      tester.element(find.byType(RutasScreen)),
    ).read(dificultadRutasProvider.notifier).state = dificultad;
    await tester.pumpAndSettle();
  }

  List<RangoDistancia> elegidos(WidgetTester tester) => [
    for (final rango in RangoDistancia.values)
      if (tester
          .widget<ChipFiltro>(find.byKey(RutasScreen.claveRango(rango)))
          .activo)
        rango,
  ];

  group('cada rango (criterios 1 y 2)', () {
    testWidgets('cada uno muestra solo las rutas cuya distancia total cae en '
        'él, en el orden por cercanía', (tester) async {
      await abrirRutas(tester);
      expect(enPantalla(tester), nombres);

      // Lo que mide cada ruta, no lo lejos que queda: la segunda más
      // cercana mide 15 km.
      const esperadas = {
        RangoDistancia.menosDe5: ['Vuelta al parque'],
        // 5 y 10 km justos son de este rango, y también la de 4,996 km, que
        // se ve como "5 km". La de 7,50 km llegó como texto.
        RangoDistancia.de5a10: [
          'Loma de los Balsos',
          'Casi cinco por el río',
          'Circuito del estadio',
          'Cerro Volador',
        ],
        // 20 km justos son de este rango, no del siguiente.
        RangoDistancia.de10a20: ['Subida a Santa Elena', 'Travesía a Guatapé'],
        RangoDistancia.masDe20: ['Ultra del Oriente'],
      };
      for (final MapEntry(key: rango, value: rutas) in esperadas.entries) {
        await tocarRango(tester, rango);

        expect(elegidos(tester), [rango]);
        expect(enPantalla(tester), rutas, reason: rango.etiqueta);
        expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      }
    });

    testWidgets('la tarjeta dice lo que mide cada una, y cuadra con el rango', (
      tester,
    ) async {
      await abrirRutas(tester);

      await tocarRango(tester, RangoDistancia.de5a10);

      for (final (nombre, km) in [
        ('Loma de los Balsos', '5 km'),
        ('Casi cinco por el río', '5 km'),
        ('Circuito del estadio', '10 km'),
        ('Cerro Volador', '7.5 km'),
      ]) {
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text(nombre),
              matching: find.byType(TarjetaRutaExplorar),
            ),
            matching: find.text(km),
          ),
          findsOneWidget,
          reason: nombre,
        );
      }
    });

    testWidgets('cada ruta con distancia sale en un solo rango, y la que no '
        'la tiene, en ninguno', (tester) async {
      await abrirRutas(tester);

      final vistas = <String>[];
      for (final rango in RangoDistancia.values) {
        await tocarRango(tester, rango);
        vistas.addAll(enPantalla(tester));
      }

      expect(vistas, hasLength(vistas.toSet().length));
      expect(vistas.toSet(), {...nombres}..remove('Paseo sin medir'));
    });

    testWidgets('cambiar de rango no vuelve a consultar la base', (
      tester,
    ) async {
      await abrirRutas(tester);
      expect(base.consultasCercanas, 1);

      for (final rango in RangoDistancia.values) {
        await tocarRango(tester, rango);
      }

      expect(base.consultasCercanas, 1);
      expect(base.consultasPublicadas, 0);
    });

    testWidgets('sin saber dónde está el usuario, filtra igual las más '
        'recientes', (tester) async {
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      await abrirRutas(tester);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);

      await tocarRango(tester, RangoDistancia.de10a20);

      expect(enPantalla(tester), [
        'Subida a Santa Elena',
        'Travesía a Guatapé',
      ]);
      expect(base.consultasPublicadas, 1);
      expect(base.consultasCercanas, 0);
    });
  });

  group('la combinación con la dificultad (criterio 3)', () {
    testWidgets('con dificultad y rango, solo las que cumplen las dos', (
      tester,
    ) async {
      await abrirRutas(tester);

      await elegirDificultad(tester, Dificultad.facil);
      expect(enPantalla(tester), [
        'Vuelta al parque',
        'Subida a Santa Elena',
        'Casi cinco por el río',
      ]);

      await tocarRango(tester, RangoDistancia.de5a10);
      expect(enPantalla(tester), ['Casi cinco por el río']);

      await elegirDificultad(tester, Dificultad.moderada);
      expect(enPantalla(tester), ['Loma de los Balsos', 'Cerro Volador']);

      await tocarRango(tester, RangoDistancia.de10a20);
      expect(enPantalla(tester), ['Travesía a Guatapé']);

      // Cada tarjeta dice la dificultad por la que pasó.
      expect(
        find.descendant(
          of: find.byType(TarjetaRutaExplorar),
          matching: find.text('Moderada'),
        ),
        findsOneWidget,
      );
      expect(base.consultasCercanas, 1);
    });

    testWidgets('también sobre los resultados de una búsqueda, sin buscar '
        'otra vez', (tester) async {
      // Las de Ana Gómez: 3,2, 5 y 20 km.
      base.encontradas = [
        for (final fila in [parque, balsos, guatape])
          {...fila, 'distancia_usuario_km': 1.0},
      ];
      await abrirRutas(tester);
      // Elegida antes de buscar: tiene que sobrevivir a la espera.
      await elegirDificultad(tester, Dificultad.moderada);

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), 'ana');
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(enPantalla(tester), ['Loma de los Balsos', 'Travesía a Guatapé']);

      await tocarRango(tester, RangoDistancia.de5a10);

      expect(enPantalla(tester), ['Loma de los Balsos']);
      expect(base.busquedas, 1);
    });

    testWidgets('si ninguna cumple las dos, dice cuál filtro las deja fuera', (
      tester,
    ) async {
      await abrirRutas(tester);

      await elegirDificultad(tester, Dificultad.dificil);
      await tocarRango(tester, RangoDistancia.menosDe5);

      expect(find.byType(TarjetaRutaExplorar), findsNothing);
      expect(
        find.text('Ninguna ruta difícil de menos de 5 km'),
        findsOneWidget,
      );
      // Hay difíciles y hay de menos de 5 km, pero no las dos cosas.
      expect(
        find.text(
          'Hay rutas difíciles y rutas de menos de 5 km, pero ninguna que '
          'cumpla las dos. Prueba quitando uno de los filtros.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con las filas de hoy, que no traen dificultad, todas van sin '
        'clasificar y ninguna pasa por una dificultad', (tester) async {
      base.cercanas = [
        for (final fila in base.cercanas) {...fila}..remove('dificultad'),
      ];
      await abrirRutas(tester);
      expect(
        find.text(TarjetaRutaExplorar.sinDificultad),
        findsNWidgets(todas.length),
      );

      await elegirDificultad(tester, Dificultad.facil);

      expect(find.byType(TarjetaRutaExplorar), findsNothing);
      expect(find.text('Ninguna ruta fácil'), findsOneWidget);
      expect(find.text(RutasScreen.pruebaOtraDificultad), findsOneWidget);
    });
  });

  group('el retiro del filtro (criterio 4)', () {
    testWidgets('tocar otra vez el rango elegido lo quita: vuelve la lista '
        'completa, en su orden y sin consultar', (tester) async {
      await abrirRutas(tester);
      await tocarRango(tester, RangoDistancia.de10a20);
      expect(enPantalla(tester), [
        'Subida a Santa Elena',
        'Travesía a Guatapé',
      ]);

      await tocarRango(tester, RangoDistancia.de10a20);

      expect(elegidos(tester), isEmpty);
      expect(enPantalla(tester), nombres);
      expect(base.consultasCercanas, 1);
    });

    testWidgets('quitar la dificultad deja el rango elegido', (tester) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.facil);
      await tocarRango(tester, RangoDistancia.de10a20);
      expect(enPantalla(tester), ['Subida a Santa Elena']);

      await elegirDificultad(tester, null);

      expect(elegidos(tester), [RangoDistancia.de10a20]);
      expect(enPantalla(tester), [
        'Subida a Santa Elena',
        'Travesía a Guatapé',
      ]);
    });

    testWidgets('sin resultados, «Quitar los filtros» quita los dos', (
      tester,
    ) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.dificil);
      await tocarRango(tester, RangoDistancia.menosDe5);

      await tester.tap(find.byKey(RutasScreen.claveQuitarFiltros));
      await tester.pumpAndSettle();

      expect(elegidos(tester), isEmpty);
      expect(enPantalla(tester), nombres);
      expect(base.consultasCercanas, 1);
    });

    testWidgets('al salir de la sección se olvidan: al volver empieza sin '
        'filtros', (tester) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.facil);
      await tocarRango(tester, RangoDistancia.menosDe5);

      await tester.tap(find.text(SeccionPrincipal.inicio.etiqueta));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SeccionPrincipal.rutas.etiqueta));
      await tester.pumpAndSettle();

      expect(elegidos(tester), isEmpty);
      expect(enPantalla(tester), nombres);
      // Al entrar de nuevo se consulta otra vez, como siempre (SCRUM-246).
      expect(base.consultasCercanas, 2);
    });
  });

  group('el aviso al lector de pantalla (criterio 5)', () {
    /// Lo que la app le anuncia al lector de pantalla.
    List<String> escucharAnuncios(WidgetTester tester) {
      final anuncios = <String>[];
      final mensajero = tester.binding.defaultBinaryMessenger;
      mensajero.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        (mensaje) async {
          if (mensaje case {
            'type': 'announce',
            'data': {'message': final String texto},
          }) {
            anuncios.add(texto);
          }
          return null;
        },
      );
      addTearDown(
        () => mensajero.setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
      );
      return anuncios;
    }

    /// Desliza la lista hacia abajo, como el usuario para recargarla: media
    /// lista, porque el indicador pide arrastrar un cuarto de lo que mide.
    Future<void> recargar(WidgetTester tester) async {
      final lista = find.byKey(RutasScreen.claveLista);
      await tester.fling(
        lista,
        Offset(0, tester.getSize(lista).height / 2),
        1000,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('cuando los filtros dejan la lista vacía lo anuncia, y al '
        'recargar, solo si cambió lo que dice', (tester) async {
      final anuncios = escucharAnuncios(tester);
      await abrirRutas(tester);

      await elegirDificultad(tester, Dificultad.facil);
      await tocarRango(tester, RangoDistancia.masDe20);
      const primero =
          'Ninguna ruta fácil de más de 20 km. Hay rutas fáciles y rutas de '
          'más de 20 km, pero ninguna que cumpla las dos. Prueba quitando uno '
          'de los filtros.';
      expect(anuncios, [primero]);

      // La misma lista: no hay nada nuevo que decir.
      await recargar(tester);
      expect(base.consultasCercanas, 2);
      expect(anuncios, [primero]);

      // Ya no queda ninguna de más de 20 km: ahora el que estorba es el
      // rango, y el mensaje lo dice.
      base.cercanas = [
        for (final fila in base.cercanas)
          if (fila['id'] != 'r-oriente') fila,
      ];
      await recargar(tester);

      expect(base.consultasCercanas, 3);
      expect(anuncios, [
        primero,
        'Ninguna ruta fácil de más de 20 km. Hay rutas fáciles, pero ninguna '
            'de más de 20 km. Prueba con otro rango.',
      ]);
    });
  });
}

/// Una fila de rutas como la devuelven las consultas de la base, con la
/// dificultad como la guardará `rutas.dificultad` (SCRUM-363).
Map<String, Object?> _fila(
  String id,
  String nombre, {
  required String autor,
  required Object? distancia,
  Dificultad? dificultad,
}) => {
  'id': id,
  'autor_id': 'autor-$id',
  'autor_nombre': autor,
  'entrenamiento_id': 'entrenamiento-$id',
  'nombre': nombre,
  'descripcion': null,
  'distancia_km': distancia,
  'estado': 'publicada',
  'motivo_rechazo': null,
  'fecha_creacion': '2026-10-10T14:00:00Z',
  'fecha_publicacion': '2026-10-10T14:00:00Z',
  'miniatura': [
    {'lat': 6.2442, 'lng': -75.5812},
    {'lat': 6.2444, 'lng': -75.5802},
  ],
  'dificultad': ?dificultad?.valorDb,
};

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// La base como la ve la app a través de PostgREST: `rutas_cercanas`,
/// `buscar_rutas` y las publicadas de `rutas`. Contesta lo que la prueba le
/// indique y cuenta lo que se le pidió.
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

  /// Lo que devuelve `rutas_cercanas`, de la más cercana a la más lejana.
  List<Map<String, Object?>> cercanas = const [];

  /// Las publicadas, para cuando no se sabe dónde está el usuario.
  List<Map<String, Object?>> publicadas = const [];

  /// Lo que devuelve `buscar_rutas`. La base es la que decide qué coincide;
  /// aquí lo decide la prueba.
  List<Map<String, Object?>> encontradas = const [];

  int consultasCercanas = 0;
  int consultasPublicadas = 0;
  int busquedas = 0;

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
      busquedas++;
      return _json(encontradas, peticion);
    }
    if (peticion.method == 'GET' &&
        url.path == '/rest/v1/rutas' &&
        url.queryParameters['estado'] == 'eq.publicada') {
      consultasPublicadas++;
      return _json(publicadas, peticion);
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
