// Pruebas de integración de filtrar rutas por dificultad (HU-36, SCRUM-271):
// cada dificultad, el regreso a la lista completa y la combinación con la
// búsqueda de HU-30.
//
// Monta la sección de Rutas tal como la registra la app (`seccionRutas`),
// con el repositorio de verdad. Solo se reemplaza lo que necesita red o
// teléfono: Supabase contesta desde un cliente HTTP falso, como contestaría
// PostgREST; los lugares salen de un buscador falso, y la ubicación y los
// permisos, de fuentes falsas.
//
// Lo que estas pruebas NO prueban:
// - La dificultad que guarda la base. `rutas.dificultad` todavía no existe
//   (la crea SCRUM-363): las filas de aquí la traen como la traerá, con los
//   valores de `Dificultad.valorDb`. Lo que pasa hoy, sin ella, está en
//   `filtrar_rutas_test.dart`.
// - Cómo busca la base. Eso es de `buscar_rutas` (0040 y 0041): aquí la base
//   falsa compara igual, y lo que se comprueba es qué hace la app con lo que
//   vuelve cuando además hay una dificultad elegida.

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
import 'package:traza/utils/texto_para_buscar.dart';
import 'package:traza/widgets/chip_filtro.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/buscador_de_zonas_falso.dart';
import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 18, 12);

  // Siete rutas de la comunidad, de la más cercana a la más lejana: dos de
  // cada dificultad y una que nadie ha clasificado.
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
    dificultad: Dificultad.moderada,
  );
  final balsos = _fila(
    'r-balsos',
    'Loma de los Balsos',
    autor: 'Ana Gómez',
    distancia: 5,
    dificultad: Dificultad.dificil,
  );
  final represa = _fila(
    'r-represa',
    'Vuelta a la represa',
    autor: 'Marta',
    distancia: 8,
    dificultad: Dificultad.facil,
  );
  final estadio = _fila(
    'r-estadio',
    'Circuito del estadio',
    autor: 'Luis Pérez',
    distancia: 10,
    dificultad: Dificultad.moderada,
  );
  final picacho = _fila(
    'r-picacho',
    'Ascenso al Picacho',
    autor: 'Marta',
    distancia: 12,
    dificultad: Dificultad.dificil,
  );
  final sinClasificar = _fila(
    'r-sin-clasificar',
    'Paseo sin clasificar',
    autor: 'Ana Gómez',
    distancia: 4.5,
  );
  final todas = [
    parque,
    santaElena,
    balsos,
    represa,
    estadio,
    picacho,
    sinClasificar,
  ];
  final nombres = [for (final fila in todas) fila['nombre']! as String];

  /// "Todas" y las tres dificultades, en el orden de la fila.
  const opciones = <Dificultad?>[null, ...Dificultad.values];

  late _BaseFalsa base;
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;

  setUp(() {
    base = _BaseFalsa()
      ..rutas = todas
      ..cercanas = [
        for (final (i, fila) in todas.indexed)
          {...fila, 'distancia_usuario_km': 0.4 + i * 0.6},
      ];

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
          buscadorDeZonasProvider.overrideWithValue(
            BuscadorDeZonasFalso(zonas: {'envigado': envigado}),
          ),
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

  /// Toca un chip de filtro como el usuario: si la fila no lo deja ver,
  /// primero la desliza.
  Future<void> tocarChip(WidgetTester tester, Key clave) async {
    final chip = find.byKey(clave);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// Toca el chip de una dificultad, o el de "Todas" con null.
  Future<void> elegirDificultad(WidgetTester tester, Dificultad? dificultad) =>
      tocarChip(tester, RutasScreen.claveDificultad(dificultad));

  ChipFiltro chipDe(WidgetTester tester, Dificultad? opcion) => tester
      .widget<ChipFiltro>(find.byKey(RutasScreen.claveDificultad(opcion)));

  /// La opción que se ve marcada: null es "Todas". Tiene que haber una sola.
  Dificultad? marcada(WidgetTester tester) {
    final marcadas = [
      for (final opcion in opciones)
        if (chipDe(tester, opcion).activo) opcion,
    ];
    expect(marcadas, hasLength(1));
    return marcadas.single;
  }

  Future<void> buscar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
    await tester.pump(esperaBusquedaRutas);
    await tester.pumpAndSettle();
  }

  String escrito(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(RutasScreen.claveBusqueda),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  group('cada dificultad (criterios 1 y 2)', () {
    testWidgets('la fila ofrece «Todas» y las tres dificultades, y empieza en '
        '«Todas», con la lista completa', (tester) async {
      await abrirRutas(tester);

      expect(
        [for (final opcion in opciones) chipDe(tester, opcion).texto],
        ['Todas', 'Fácil', 'Moderada', 'Difícil'],
      );
      expect(marcada(tester), isNull);
      expect(enPantalla(tester), nombres);
    });

    testWidgets('cada dificultad muestra solo sus rutas, en el orden por '
        'cercanía, con su chip marcado y la dificultad en cada tarjeta', (
      tester,
    ) async {
      await abrirRutas(tester);

      const esperadas = {
        Dificultad.facil: ['Vuelta al parque', 'Vuelta a la represa'],
        Dificultad.moderada: ['Subida a Santa Elena', 'Circuito del estadio'],
        Dificultad.dificil: ['Loma de los Balsos', 'Ascenso al Picacho'],
      };
      for (final MapEntry(key: dificultad, value: rutas) in esperadas.entries) {
        await elegirDificultad(tester, dificultad);

        expect(marcada(tester), dificultad);
        expect(enPantalla(tester), rutas, reason: dificultad.etiqueta);
        expect(
          find.descendant(
            of: find.byType(TarjetaRutaExplorar),
            matching: find.text(dificultad.etiqueta),
          ),
          findsNWidgets(rutas.length),
        );
        expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      }
    });

    testWidgets('cada ruta clasificada sale en una sola dificultad, y la que '
        'no está clasificada, en ninguna', (tester) async {
      await abrirRutas(tester);

      final vistas = <String>[];
      for (final dificultad in Dificultad.values) {
        await elegirDificultad(tester, dificultad);
        vistas.addAll(enPantalla(tester));
      }

      expect(vistas, hasLength(vistas.toSet().length));
      expect(vistas.toSet(), {...nombres}..remove('Paseo sin clasificar'));
    });

    testWidgets('pasar de una dificultad a otra no vuelve a consultar la '
        'base', (tester) async {
      await abrirRutas(tester);
      expect(base.consultasCercanas, 1);

      for (final dificultad in Dificultad.values) {
        await elegirDificultad(tester, dificultad);
      }

      expect(base.consultasCercanas, 1);
    });
  });

  group('el regreso a la lista completa (criterio 3)', () {
    testWidgets('«Todas» devuelve la lista completa, en su orden y sin '
        'consultar', (tester) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.moderada);

      await elegirDificultad(tester, null);

      expect(marcada(tester), isNull);
      expect(enPantalla(tester), nombres);
      expect(base.consultasCercanas, 1);
    });

    testWidgets('tocar otra vez la dificultad elegida también la devuelve', (
      tester,
    ) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.dificil);

      await elegirDificultad(tester, Dificultad.dificil);

      expect(marcada(tester), isNull);
      expect(enPantalla(tester), nombres);
    });

    testWidgets('si una dificultad deja la lista vacía, lo dice, y «Quitar el '
        'filtro» la devuelve', (tester) async {
      await abrirRutas(tester);
      await buscar(tester, 'parque');
      expect(enPantalla(tester), ['Vuelta al parque']);

      await elegirDificultad(tester, Dificultad.dificil);

      expect(find.byType(TarjetaRutaExplorar), findsNothing);
      expect(find.text('Ninguna ruta difícil'), findsOneWidget);
      expect(find.text(RutasScreen.pruebaOtraDificultad), findsOneWidget);

      await tester.tap(find.byKey(RutasScreen.claveQuitarFiltros));
      await tester.pumpAndSettle();

      expect(marcada(tester), isNull);
      expect(enPantalla(tester), ['Vuelta al parque']);
      expect(base.busquedas, hasLength(1));
    });
  });

  group('la combinación con la búsqueda (criterio 4)', () {
    testWidgets('buscar y después elegir una dificultad deja solo los '
        'resultados de esa dificultad, sin buscar otra vez ni borrar lo '
        'escrito', (tester) async {
      await abrirRutas(tester);
      // Las de Ana Gómez.
      await buscar(tester, 'ana');
      expect(enPantalla(tester), [
        'Vuelta al parque',
        'Loma de los Balsos',
        'Paseo sin clasificar',
      ]);

      await elegirDificultad(tester, Dificultad.dificil);

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(enPantalla(tester), ['Loma de los Balsos']);
      expect(escrito(tester), 'ana');
      expect(base.busquedas, hasLength(1));
    });

    testWidgets('elegir una dificultad y después buscar: los resultados '
        'llegan filtrados y la dificultad sigue elegida', (tester) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.facil);

      // Las de Marta: una fácil y una difícil.
      await buscar(tester, 'marta');

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(enPantalla(tester), ['Vuelta a la represa']);
      expect(marcada(tester), Dificultad.facil);
    });

    testWidgets('al borrar la búsqueda vuelven las cercanas, todavía '
        'filtradas', (tester) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.moderada);
      await buscar(tester, 'luis');
      expect(enPantalla(tester), [
        'Subida a Santa Elena',
        'Circuito del estadio',
      ]);

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), '');
      await tester.pumpAndSettle();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(marcada(tester), Dificultad.moderada);
      expect(enPantalla(tester), [
        'Subida a Santa Elena',
        'Circuito del estadio',
      ]);
      // Las cercanas no se volvieron a pedir (HU-30, criterio 5).
      expect(base.consultasCercanas, 1);
    });

    testWidgets('con la búsqueda por lugar, la dificultad se aplica a las que '
        'arrancan ahí', (tester) async {
      base.enZona = [balsos, picacho, santaElena];
      await abrirRutas(tester);
      await buscar(tester, 'envigado');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(base.busquedas.last.containsKey('p_zona_sur'), isTrue);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);
      expect(enPantalla(tester), [
        'Loma de los Balsos',
        'Ascenso al Picacho',
        'Subida a Santa Elena',
      ]);
      final busquedas = base.busquedas.length;

      await elegirDificultad(tester, Dificultad.dificil);

      expect(enPantalla(tester), ['Loma de los Balsos', 'Ascenso al Picacho']);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);
      expect(base.busquedas, hasLength(busquedas));
    });

    testWidgets('si la búsqueda no encuentra nada, lo dice la búsqueda y no '
        'el filtro', (tester) async {
      await abrirRutas(tester);
      await elegirDificultad(tester, Dificultad.facil);

      await buscar(tester, 'zzz');

      expect(find.byKey(RutasScreen.claveSinResultados), findsOneWidget);
      expect(find.byKey(RutasScreen.claveSinRutasConFiltros), findsNothing);
      expect(marcada(tester), Dificultad.facil);
    });
  });
}

/// Una fila de rutas como la devuelven las consultas de la base, con la
/// dificultad como la guardará `rutas.dificultad` (SCRUM-363).
Map<String, Object?> _fila(
  String id,
  String nombre, {
  required String autor,
  required double distancia,
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

/// La base como la ve la app a través de PostgREST: `rutas_cercanas` y
/// `buscar_rutas`. Cuenta lo que se le pidió.
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

  /// Las publicadas, de la más cercana a la más lejana: en las que se busca.
  List<Map<String, Object?>> rutas = const [];

  /// Lo que devuelve `rutas_cercanas`: las mismas, con lo lejos que quedan.
  List<Map<String, Object?>> cercanas = const [];

  /// Las que arrancan en el lugar de una búsqueda confirmada.
  List<Map<String, Object?>> enZona = const [];

  int consultasCercanas = 0;

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
      return _json(_buscar(parametros), peticion);
    }

    inesperadas.add('${peticion.method} $url');
    return http.Response('', 404, request: peticion);
  }

  /// Como compara la base (0041): cada palabra escrita tiene que ser el
  /// comienzo de una palabra del nombre o de quien publicó la ruta. Con un
  /// lugar confirmado, suma las que arrancan en él.
  List<Map<String, Object?>> _buscar(Map<String, Object?> parametros) {
    final palabras = textoParaBuscar(
      parametros['p_termino']! as String,
    ).split(' ');
    bool coincide(Map<String, Object?> fila) {
      final texto =
          ' ${textoParaBuscar('${fila['nombre']} ${fila['autor_nombre']}')}';
      return palabras.every((palabra) => texto.contains(' $palabra'));
    }

    final porTexto = [
      for (final fila in rutas)
        if (coincide(fila)) fila,
    ];
    return [
      ...porTexto,
      if (parametros.containsKey('p_zona_sur'))
        for (final fila in enZona)
          if (!porTexto.contains(fila)) fila,
    ];
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
