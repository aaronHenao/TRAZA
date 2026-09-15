import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/services/tipos_actividad_service.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/screens/summary/resumen_screen.dart';
import 'package:traza/screens/tracking/tracking_con_actividad_elegida.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/controles_entrenamiento.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

/// Pruebas de la parte B de SCRUM-93 y de la verificación que SCRUM-95 dejó
/// pendiente (la pantalla del entrenamiento en curso de Aaron recibe la
/// actividad que el usuario eligió en los chips del inicio), y del cierre de
/// la actividad con paso al resumen (SCRUM-121).
///
/// La pantalla se monta con los mismos falsos que usan las pruebas de Aaron
/// (`test/screens/tracking_screen_test.dart`), para no tocar el GPS real.
void main() {
  testWidgets('con una actividad elegida, la pantalla del entrenamiento la '
      'recibe y la muestra', (tester) async {
    final entorno = await _montar(tester, catalogo: _catalogo, elegir: 'Trote');

    final pantalla = tester.widget<TrackingScreen>(find.byType(TrackingScreen));
    expect(pantalla.nombreActividad, 'Trote');
    expect(find.text('Trote'), findsWidgets);

    entorno.detenerCronometro();
  });

  testWidgets('sin sesión, aunque se elija otra, abre con la actividad por '
      'defecto de la pantalla', (tester) async {
    // Sin sesión el catálogo es el local, sin ids: no hay configuración de
    // inicio y la pantalla usa su valor por defecto ("Correr").
    final entorno = await _montar(
      tester,
      catalogo: TipoActividad.catalogoLocal,
      elegir: 'Trote',
    );

    final pantalla = tester.widget<TrackingScreen>(find.byType(TrackingScreen));
    expect(pantalla.nombreActividad, 'Correr');

    entorno.detenerCronometro();
  });

  group('al finalizar la actividad (SCRUM-121)', () {
    testWidgets('cierra el entrenamiento y abre el resumen', (tester) async {
      final entorno = await _montar(
        tester,
        catalogo: _catalogo,
        elegir: 'Trote',
      );
      entorno.container
          .read(actividadIniciadaProvider.notifier)
          .marcarIniciada();

      await entorno.correr(tester, const Duration(minutes: 32, seconds: 17));
      await _tocarFinalizar(tester);

      final cierre = entorno.entrenamientos.cierres.single;
      expect(cierre.entrenamientoId, 'e-123');
      expect(cierre.duracion, const Duration(minutes: 32, seconds: 17));
      expect(cierre.fechaFin, DateTime(2026, 1, 1, 8, 32, 17));
      // Todavía no hay cálculo de distancia (SCRUM-111 y SCRUM-112).
      expect(cierre.distanciaMetros, isNull);

      expect(find.byType(ResumenScreen), findsOneWidget);
      expect(find.byType(TrackingScreen), findsNothing);
      expect(entorno.container.read(actividadIniciadaProvider), isFalse);

      // El resumen es el de la sesión que acaba de terminar (SCRUM-117).
      expect(find.text('Trote · hoy'), findsOneWidget);
      expect(find.text('00:32:17'), findsOneWidget);
      // El id del entrenamiento viaja en la ruta (SCRUM-122).
      expect(entorno.ubicacion, '/resumen/e-123');
    });

    testWidgets('guarda los puntos GPS y también cierra el entrenamiento', (
      tester,
    ) async {
      final entorno = await _montar(
        tester,
        catalogo: _catalogo,
        elegir: 'Correr',
      );
      await entorno.registrarPunto(tester);

      await _tocarFinalizar(tester);

      expect(entorno.puntos.lotes.single.entrenamientoId, 'e-123');
      expect(entorno.puntos.lotes.single.puntos, hasLength(1));
      expect(entorno.entrenamientos.cierres, hasLength(1));
      expect(find.byType(ResumenScreen), findsOneWidget);
    });

    testWidgets('sin entrenamiento creado abre el resumen sin actualizar '
        'nada', (tester) async {
      // Todavía no hay login ni SCRUM-99, así que no hay fila que cerrar.
      final entorno = await _montar(
        tester,
        catalogo: _catalogo,
        elegir: 'Correr',
        entrenamientoId: null,
      );

      await _tocarFinalizar(tester);

      expect(entorno.entrenamientos.cierres, isEmpty);
      expect(find.byType(ResumenScreen), findsOneWidget);
      // Sin sesión no hay id: el resumen va a `/resumen` con los datos de la
      // sesión local.
      expect(entorno.ubicacion, '/resumen');
      expect(find.text('Correr · hoy'), findsOneWidget);
    });

    testWidgets('si no se pudo cerrar el entrenamiento se queda en la '
        'actividad, lo avisa y permite reintentar', (tester) async {
      final entorno = await _montar(
        tester,
        catalogo: _catalogo,
        elegir: 'Correr',
      );
      entorno.container
          .read(actividadIniciadaProvider.notifier)
          .marcarIniciada();
      entorno.entrenamientos.fallar = true;

      await _tocarFinalizar(tester);

      expect(
        find.text('No se pudo guardar el entrenamiento. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(find.byType(ResumenScreen), findsNothing);
      expect(entorno.container.read(actividadIniciadaProvider), isTrue);

      // Se recupera la conexión y el usuario vuelve a tocar "Finalizar".
      entorno.entrenamientos.fallar = false;
      await _tocarFinalizar(tester);

      expect(entorno.entrenamientos.cierres, hasLength(1));
      expect(find.byType(ResumenScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('si los puntos no se guardaron no da el entrenamiento por '
        'finalizado', (tester) async {
      final entorno = await _montar(
        tester,
        catalogo: _catalogo,
        elegir: 'Correr',
      );
      await entorno.registrarPunto(tester);
      entorno.puntos.fallar = true;

      await _tocarFinalizar(tester);

      expect(
        find.text('No se pudo guardar el recorrido. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(entorno.entrenamientos.cierres, isEmpty);
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(find.byType(ResumenScreen), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
      'al descartar la actividad no se muestra ningún resumen (SCRUM-122)',
      (tester) async {
        final entorno = await _montar(
          tester,
          catalogo: _catalogo,
          elegir: 'Correr',
        );

        // El cronómetro sigue en marcha, así que se avanza a mano en vez de
        // esperar a que la pantalla quede quieta.
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Descartar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(ResumenScreen), findsNothing);
        expect(entorno.entrenamientos.cierres, isEmpty);
        expect(entorno.ubicacion, '/tracking');
      },
    );
  });
}

const _catalogo = [
  TipoActividad(id: 'id-correr', nombre: 'Correr'),
  TipoActividad(id: 'id-trote', nombre: 'Trote'),
  TipoActividad(id: 'id-caminar', nombre: 'Caminar'),
];

class _CatalogoFalso implements TiposActividadRepository {
  const _CatalogoFalso(this.tipos);

  final List<TipoActividad> tipos;

  @override
  Future<List<TipoActividad>> cargar() async => tipos;
}

/// Registro de una llamada a `finalizar`.
typedef _Cierre = ({
  String entrenamientoId,
  DateTime fechaFin,
  Duration duracion,
  double? distanciaMetros,
});

/// Repositorio de entrenamientos en memoria: anota cada cierre y, si la
/// prueba lo indica, falla.
class _EntrenamientosFalso implements EntrenamientoRepository {
  final cierres = <_Cierre>[];

  bool fallar = false;

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError('Al finalizar, el resumen llega sin consultar');

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) async {
    if (fallar) throw StateError('Supabase no disponible');
    cierres.add((
      entrenamientoId: entrenamientoId,
      fechaFin: fechaFin,
      duracion: duracion,
      distanciaMetros: distanciaMetros,
    ));
  }
}

/// Lo que cada prueba necesita controlar de la pantalla montada.
class _Entorno {
  _Entorno({
    required this.container,
    required this.reloj,
    required this.fuente,
    required this.puntos,
    required this.entrenamientos,
    required this.router,
  });

  final ProviderContainer container;
  final GoRouter router;
  final RelojFalso reloj;
  final FuenteUbicacionFalsa fuente;
  final RepositorioPuntosGpsFalso puntos;
  final _EntrenamientosFalso entrenamientos;

  /// Ruta en la que está la app ahora.
  String get ubicacion =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// Hace correr el tiempo de la actividad, igual que en las pruebas de Aaron.
  Future<void> correr(WidgetTester tester, Duration cuanto) async {
    reloj.avanzar(cuanto);
    await tester.pump(cuanto);
  }

  /// El GPS entrega una lectura mientras la actividad está en curso.
  Future<void> registrarPunto(WidgetTester tester) async {
    fuente.emitir(puntoDePrueba());
    await tester.pump();
    await tester.pump();
  }

  /// Igual que en las pruebas de Aaron: se detiene el cronómetro antes de
  /// terminar para no dejar su temporizador vivo.
  void detenerCronometro() =>
      container.read(cronometroProvider.notifier).detener();
}

/// Hace lo mismo que los chips del inicio (carga el catálogo y elige
/// [elegir]) y después abre la pantalla del entrenamiento, con el resumen
/// como siguiente destino.
Future<_Entorno> _montar(
  WidgetTester tester, {
  required List<TipoActividad> catalogo,
  required String elegir,
  String? entrenamientoId = 'e-123',
}) async {
  final reloj = RelojFalso();
  final fuente = FuenteUbicacionFalsa();
  addTearDown(fuente.cerrar);
  final puntos = RepositorioPuntosGpsFalso();
  final entrenamientos = _EntrenamientosFalso();

  final container = ProviderContainer(
    overrides: [
      relojProvider.overrideWithValue(reloj.call),
      fuenteUbicacionProvider.overrideWithValue(fuente),
      proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
      repositorioPuntosGpsProvider.overrideWithValue(puntos),
      entrenamientoActualProvider.overrideWithValue(entrenamientoId),
      entrenamientoRepositoryProvider.overrideWithValue(entrenamientos),
      tiposActividadRepositoryProvider.overrideWithValue(
        _CatalogoFalso(catalogo),
      ),
    ],
  );
  addTearDown(container.dispose);

  final tipos = await container.read(tiposActividadProvider.future);
  container
      .read(actividadSeleccionadaProvider.notifier)
      .seleccionar(tipos.firstWhere((tipo) => tipo.nombre == elegir));

  final router = GoRouter(
    initialLocation: '/tracking',
    routes: [
      GoRoute(
        path: '/tracking',
        builder: (_, _) => const TrackingConActividadElegida(),
      ),
      // Las mismas rutas del resumen que en main.dart.
      GoRoute(
        path: '/resumen',
        builder: (_, estado) => ResumenScreen.desdeRuta(estado),
        routes: [
          GoRoute(
            path: ':entrenamientoId',
            builder: (_, estado) => ResumenScreen.desdeRuta(estado),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // La pantalla inicia el cronómetro en el primer frame.
  await tester.pump();

  return _Entorno(
    container: container,
    reloj: reloj,
    fuente: fuente,
    puntos: puntos,
    entrenamientos: entrenamientos,
    router: router,
  );
}

/// Toca "Finalizar" y espera a que se guarden los puntos, se cierre el
/// entrenamiento y termine la transición (o aparezca el aviso).
///
/// `pumpAndSettle` es seguro aquí: al finalizar, el cronómetro se detiene y
/// deja de refrescar la pantalla.
Future<void> _tocarFinalizar(WidgetTester tester) async {
  await tester.tap(find.byKey(ControlesEntrenamiento.claveFinalizar));
  await tester.pumpAndSettle();
}
