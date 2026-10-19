import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/mapa_trayecto.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';

import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas del detalle de una ruta (SCRUM-240): que diga cuánto mide sin que
/// haya que empezar nada, y que lo diga también cuando no lo sabe.
///
/// SCRUM-358 agrega el recorrido completo sobre el mapa: verlo entero, con su
/// inicio y su final, moverse por él, salir sin registrar nada y reintentar
/// cuando no carga.
void main() {
  Ruta ruta({
    double? distanciaKm = 5.23,
    String? descripcion,
    List<PuntoRuta> trazado = const [
      PuntoRuta(latitud: 6.2442, longitud: -75.5812),
      PuntoRuta(latitud: 6.2450, longitud: -75.5800),
    ],
  }) => Ruta(
    id: 'ruta-1',
    autorId: 'usuario-9',
    autorNombre: 'Ana',
    nombre: 'Vuelta al Parque Norte',
    descripcion: descripcion,
    estado: EstadoRuta.publicada,
    distanciaKm: distanciaKm,
    trazado: trazado,
    fechaCreacion: DateTime(2026, 10, 16),
    fechaPublicacion: DateTime(2026, 10, 17, 9),
  );

  group('lo que muestra', () {
    testWidgets('el nombre, de quien es, y cuanto mide (criterios 1 y 2)', (
      tester,
    ) async {
      await _abrir(tester, rutas: [ruta(descripcion: 'Plana y con sombra.')]);

      expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
      expect(find.text('Por Ana · Hoy'), findsOneWidget);

      // La distancia, con su unidad.
      expect(find.text('5.23 km'), findsOneWidget);
      expect(find.text('Distancia total de la ruta'), findsOneWidget);

      expect(find.text('Plana y con sombra.'), findsOneWidget);

      // Criterio 2: no hay nada que iniciar para verla.
      expect(find.widgetWithText(FilledButton, 'Iniciar ruta'), findsNothing);
    });

    testWidgets('el trazado sobre el mapa', (tester) async {
      await _abrir(tester, rutas: [ruta()]);

      expect(find.byType(MapaTrayecto), findsOneWidget);
    });

    testWidgets('una ruta sin trazado no revienta el mapa', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: const [])]);

      expect(find.byType(MapaTrayecto), findsNothing);
      expect(find.text('Esta ruta no guardó su trazado'), findsOneWidget);
    });
  });

  group('sin distancia registrada (criterio 4)', () {
    testWidgets('lo dice en vez de callarselo o inventarlo', (tester) async {
      await _abrir(tester, rutas: [ruta(distanciaKm: null)]);

      expect(find.text('Distancia no disponible'), findsOneWidget);
      expect(
        find.textContaining('no podemos decirte cuánto mide'),
        findsOneWidget,
      );
      // Y no aparece ningún número inventado.
      expect(find.textContaining(' km'), findsNothing);
    });
  });

  group('cuando no se puede abrir', () {
    testWidgets('una ruta que ya no esta lo explica', (tester) async {
      await _abrir(tester, rutas: const []);

      expect(find.text('Esta ruta ya no está disponible'), findsOneWidget);
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsNothing);
    });

    testWidgets('si falla la lectura deja reintentar', (tester) async {
      final repositorio = await _abrir(
        tester,
        rutas: [ruta()],
        error: StateError('sin red'),
      );

      // SCRUM-358 (criterio 5) cambió el texto: lo que no se pudo mostrar es
      // el recorrido.
      expect(find.text('No pudimos mostrar el recorrido'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.byKey(DetalleRutaScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text('5.23 km'), findsOneWidget);
    });
  });

  group('el recorrido completo sobre el mapa (criterio 1 de SCRUM-358)', () {
    testWidgets('dibuja el trazado completo, en orden, con su punto de inicio '
        'y su punto de finalización (criterio 1 de SCRUM-358)', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: _recorrido)]);

      final linea = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single;
      expect(linea.points, _coordenadas(_recorrido));

      // La partida en el primer punto y la llegada en el último.
      final marcadores = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers;
      expect(marcadores.first.point, _coordenadas(_recorrido).first);
      expect(marcadores.last.point, _coordenadas(_recorrido).last);
      expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
      expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);
    });

    testWidgets('al abrir, el recorrido entero cabe en el mapa '
        '(criterio 1 de SCRUM-358)', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: _recorridoLargo)]);

      _esperarTodoALaVista(tester, _recorridoLargo);
    });

    testWidgets('una ruta de un solo punto marca su inicio y su final sin '
        'dibujar línea (criterio 1 de SCRUM-358)', (tester) async {
      await _abrir(
        tester,
        rutas: [
          ruta(trazado: const [PuntoRuta(latitud: 6.2442, longitud: -75.5812)]),
        ],
      );

      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
      expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);
    });
  });

  group('verlo sin iniciar nada (criterio 2 de SCRUM-358)', () {
    testWidgets('se ve el recorrido completo sin iniciar la ruta ni registrar '
        'actividad (criterio 2 de SCRUM-358)', (tester) async {
      final entrenamientos = _EntrenamientosVigilados();

      await _abrir(
        tester,
        rutas: [ruta(trazado: _recorrido)],
        entrenamientos: entrenamientos,
      );

      // Se ve entero...
      expect(find.byType(MapaTrayecto), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        _coordenadas(_recorrido),
      );
      _esperarTodoALaVista(tester, _recorrido);

      // ...y no se tocó nada de entrenamientos.
      expect(entrenamientos.llamadas, isEmpty);
      expect(_entrenamientoEnCurso(tester), isNull);
    });
  });

  group('moverse por el recorrido (criterio 3 de SCRUM-358)', () {
    testWidgets('al ampliar y desplazar el mapa el trazado sigue completo, '
        'con su inicio y su final (criterio 3 de SCRUM-358)', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: _recorrido)]);
      final antes = _camara(tester);

      await _acercarConDobleToque(tester);
      final acercada = _camara(tester);
      expect(acercada.zoom, greaterThan(antes.zoom));

      await _arrastrarMapa(tester, const Offset(60, 0));
      expect(_camara(tester).center, isNot(acercada.center));

      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        _coordenadas(_recorrido),
      );
      expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
      expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);
      _esperarTodoALaVista(tester, _recorrido);
    });

    testWidgets('al reducir el mapa el trazado sigue completo y a la vista '
        '(criterio 3 de SCRUM-358)', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: _recorrido)]);
      final antes = _camara(tester);

      await _alejarConPellizco(tester);

      expect(_camara(tester).zoom, lessThan(antes.zoom));
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        _coordenadas(_recorrido),
      );
      expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
      expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);
      _esperarTodoALaVista(tester, _recorrido);
    });

    testWidgets('acercado, se recorre el trazado de punta a punta '
        'desplazando el mapa (criterio 3 de SCRUM-358)', (tester) async {
      await _abrir(tester, rutas: [ruta(trazado: _recorridoLargo)]);
      final coordenadas = _coordenadas(_recorridoLargo);

      await _acercarConDobleToque(tester);

      // Acercado ya no cabe entero: el inicio queda fuera y hay que moverse
      // para verlo.
      expect(
        _camara(tester).visibleBounds.contains(coordenadas.first),
        isFalse,
      );

      await _llevarAlCentro(tester, coordenadas.first);
      expect(_camara(tester).visibleBounds.contains(coordenadas.first), isTrue);
      expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);

      // Desde el inicio no se alcanza a ver el final.
      expect(_camara(tester).visibleBounds.contains(coordenadas.last), isFalse);

      await _llevarAlCentro(tester, coordenadas.last);
      expect(_camara(tester).visibleBounds.contains(coordenadas.last), isTrue);
      expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);

      // Moverse no recorta la línea.
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        coordenadas,
      );
    });
  });

  group('salir sin iniciar la ruta (criterio 4 de SCRUM-358)', () {
    testWidgets('con "atrás" vuelve al listado de rutas y no registra ninguna '
        'actividad (criterio 4 de SCRUM-358)', (tester) async {
      final entrenamientos = _EntrenamientosVigilados();
      await _abrirDesdeElForo(
        tester,
        rutas: [ruta(trazado: _recorrido)],
        entrenamientos: entrenamientos,
      );

      await tester.tap(find.byKey(TarjetaRuta.claveDe('ruta-1')));
      await tester.pumpAndSettle();
      expect(find.byType(DetalleRutaScreen), findsOneWidget);
      expect(find.byType(MapaTrayecto), findsOneWidget);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      _esperarListadoDeRutas();
      expect(entrenamientos.llamadas, isEmpty);
      expect(_entrenamientoEnCurso(tester), isNull);
    });

    testWidgets('con el "atrás" del sistema también vuelve al listado sin '
        'registrar nada (criterio 4 de SCRUM-358)', (tester) async {
      final entrenamientos = _EntrenamientosVigilados();
      await _abrirDesdeElForo(
        tester,
        rutas: [ruta(trazado: _recorrido)],
        entrenamientos: entrenamientos,
      );

      await tester.tap(find.byKey(TarjetaRuta.claveDe('ruta-1')));
      await tester.pumpAndSettle();
      expect(find.byType(DetalleRutaScreen), findsOneWidget);

      // El botón atrás de Android.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      _esperarListadoDeRutas();
      expect(entrenamientos.llamadas, isEmpty);
      expect(_entrenamientoEnCurso(tester), isNull);
    });
  });

  group('cuando el recorrido no carga (criterio 5 de SCRUM-358)', () {
    testWidgets('informa que el recorrido no pudo mostrarse y ofrece '
        'reintentar (criterio 5 de SCRUM-358)', (tester) async {
      await _abrir(
        tester,
        rutas: [ruta(trazado: _recorrido)],
        error: StateError('sin red'),
      );

      expect(find.text('No pudimos mostrar el recorrido'), findsOneWidget);
      expect(find.byKey(DetalleRutaScreen.claveReintentar), findsOneWidget);
      expect(find.byType(MapaTrayecto), findsNothing);
      // Al usuario no le llega el error crudo.
      expect(find.textContaining('sin red'), findsNothing);
    });

    testWidgets('al reintentar con la lectura arreglada se ve el mapa con el '
        'trazado (criterio 5 de SCRUM-358)', (tester) async {
      final repositorio = await _abrir(
        tester,
        rutas: [ruta(trazado: _recorrido)],
        error: StateError('sin red'),
      );
      expect(find.text('No pudimos mostrar el recorrido'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.byKey(DetalleRutaScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos mostrar el recorrido'), findsNothing);
      expect(find.byType(MapaTrayecto), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .single
            .points,
        _coordenadas(_recorrido),
      );
      expect(find.byKey(MapaTrayecto.clavePartida), findsOneWidget);
      expect(find.byKey(MapaTrayecto.claveLlegada), findsOneWidget);
    });

    testWidgets('si al reintentar vuelve a fallar, lo sigue diciendo y deja '
        'reintentar otra vez (criterio 5 de SCRUM-358)', (tester) async {
      await _abrir(
        tester,
        rutas: [ruta(trazado: _recorrido)],
        error: StateError('sin red'),
      );

      await tester.tap(find.byKey(DetalleRutaScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos mostrar el recorrido'), findsOneWidget);
      expect(find.byKey(DetalleRutaScreen.claveReintentar), findsOneWidget);
      expect(find.byType(MapaTrayecto), findsNothing);
    });
  });
}

/// Un recorrido corto que no va siempre en la misma dirección, para que el
/// orden de los puntos importe. Acercado al máximo sigue cabiendo en el mapa.
const _recorrido = [
  PuntoRuta(latitud: 6.2442, longitud: -75.5812),
  PuntoRuta(latitud: 6.2445, longitud: -75.5808),
  PuntoRuta(latitud: 6.2448, longitud: -75.5809),
  PuntoRuta(latitud: 6.2447, longitud: -75.5804),
  PuntoRuta(latitud: 6.2444, longitud: -75.5802),
];

/// Un recorrido de unos 600 m que, al acercarse una vez, ya no cabe entero:
/// la partida y la llegada quedan fuera de la vista.
const _recorridoLargo = [
  PuntoRuta(latitud: 6.2700, longitud: -75.5690),
  PuntoRuta(latitud: 6.2715, longitud: -75.5665),
  PuntoRuta(latitud: 6.2735, longitud: -75.5660),
  PuntoRuta(latitud: 6.2740, longitud: -75.5640),
  PuntoRuta(latitud: 6.2725, longitud: -75.5630),
];

List<LatLng> _coordenadas(List<PuntoRuta> trazado) => [
  for (final punto in trazado) LatLng(punto.latitud, punto.longitud),
];

/// La cámara del mapa del detalle. Se lee desde la capa de la línea, que
/// siempre está, porque los marcadores fuera de la vista no se construyen.
MapCamera _camara(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(PolylineLayer)));

void _esperarTodoALaVista(WidgetTester tester, List<PuntoRuta> trazado) {
  final visible = _camara(tester).visibleBounds;
  for (final coordenada in _coordenadas(trazado)) {
    expect(
      visible.contains(coordenada),
      isTrue,
      reason: '$coordenada debería verse',
    );
  }
}

/// Acerca el mapa un nivel con un doble toque en su centro.
Future<void> _acercarConDobleToque(WidgetTester tester) async {
  final mapa = find.byType(FlutterMap);
  await tester.tap(mapa);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(mapa);
  await tester.pumpAndSettle();
  // Deja pasar la ventana del doble toque, para que el gesto siguiente no se
  // tome como "doble toque y arrastrar".
  await tester.pump(const Duration(seconds: 1));
}

/// Aleja el mapa juntando dos dedos sobre él.
Future<void> _alejarConPellizco(WidgetTester tester) async {
  final centro = tester.getCenter(find.byType(FlutterMap));
  final izquierdo = await tester.startGesture(centro - const Offset(100, 0));
  final derecho = await tester.startGesture(centro + const Offset(100, 0));
  for (var i = 0; i < 10; i++) {
    await izquierdo.moveBy(const Offset(5, 0));
    await derecho.moveBy(const Offset(-5, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await izquierdo.up();
  await derecho.up();
  await tester.pumpAndSettle();
}

/// Arrastra el mapa a 200 px/s, como un dedo que no lanza.
///
/// Más rápido (desde 800 px/s) el mapa sigue de largo por inercia; mucho más
/// lento, el dedo pasa medio segundo casi quieto y el mapa lo toma como una
/// pulsación larga en vez de un arrastre.
Future<void> _arrastrarMapa(WidgetTester tester, Offset desplazamiento) async {
  await tester.timedDragFrom(
    tester.getCenter(find.byType(FlutterMap)),
    desplazamiento,
    Duration(milliseconds: (desplazamiento.distance * 5).round()),
  );
  await tester.pumpAndSettle();
}

/// Arrastra el mapa hasta dejar [punto] cerca del centro.
Future<void> _llevarAlCentro(WidgetTester tester, LatLng punto) async {
  final camara = _camara(tester);
  final enElMapa = camara.latLngToScreenOffset(punto);
  await _arrastrarMapa(tester, camara.size.center(Offset.zero) - enElMapa);
}

/// El listado de rutas del foro, con la ruta de la prueba, y sin el detalle
/// encima.
void _esperarListadoDeRutas() {
  expect(find.byType(DetalleRutaScreen), findsNothing);
  expect(find.byType(MapaTrayecto), findsNothing);
  expect(find.byType(ForoScreen), findsOneWidget);
  expect(find.byKey(TarjetaRuta.claveDe('ruta-1')), findsOneWidget);
}

/// El entrenamiento que la app tiene en curso, o null si no hay ninguno.
String? _entrenamientoEnCurso(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Scaffold).first),
).read(entrenamientoEnCursoProvider);

/// Entrenamientos que no se deberían tocar al mirar una ruta: anota cualquier
/// llamada y falla, sin importar qué método sea.
class _EntrenamientosVigilados implements EntrenamientoRepository {
  final llamadas = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    llamadas.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}

/// Abre el foro real en su apartado de rutas, con el detalle real detrás de
/// cada tarjeta, como llega el usuario (SCRUM-241 y SCRUM-240).
Future<RutasRepositorioFalso> _abrirDesdeElForo(
  WidgetTester tester, {
  required List<Ruta> rutas,
  required _EntrenamientosVigilados entrenamientos,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final ahora = DateTime(2026, 10, 17, 12);
  final repositorio = RutasRepositorioFalso(rutas: rutas);

  final router = GoRouter(
    initialLocation: ForoScreen.ruta,
    routes: [
      GoRoute(path: ForoScreen.ruta, builder: (_, _) => const ForoScreen()),
      GoRoute(
        path: DetalleRutaScreen.ruta,
        builder: (_, estado) =>
            DetalleRutaScreen(rutaId: estado.pathParameters['rutaId']!),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        foroRepositoryProvider.overrideWithValue(
          ForoRepositorioFalso(ahora: ahora),
        ),
        usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
        fuenteCambiosForoProvider.overrideWithValue(FuenteCambiosForoFalsa()),
        rutasRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => ahora),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        entrenamientoRepositoryProvider.overrideWithValue(entrenamientos),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(ForoScreen.claveSeccion(SeccionForo.rutas)));
  await tester.pumpAndSettle();
  expect(find.byKey(TarjetaRuta.claveDe('ruta-1')), findsOneWidget);

  return repositorio;
}

Future<RutasRepositorioFalso> _abrir(
  WidgetTester tester, {
  required List<Ruta> rutas,
  Object? error,
  _EntrenamientosVigilados? entrenamientos,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = RutasRepositorioFalso(rutas: rutas, error: error);

  final router = GoRouter(
    initialLocation: DetalleRutaScreen.rutaDe('ruta-1'),
    routes: [
      GoRoute(
        path: DetalleRutaScreen.ruta,
        builder: (_, estado) =>
            DetalleRutaScreen(rutaId: estado.pathParameters['rutaId']!),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rutasRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 12)),
        // El mapa no descarga tiles reales.
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        // Mirar una ruta no debe tocar entrenamientos (SCRUM-358).
        entrenamientoRepositoryProvider.overrideWithValue(
          entrenamientos ?? _EntrenamientosVigilados(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return repositorio;
}
