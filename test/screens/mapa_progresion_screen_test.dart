import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/home/mapa_progresion_screen.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/services/rutas_oficiales_service.dart';
import 'package:traza/widgets/camino_progresion.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/rutas_oficiales_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas de la pantalla del mapa de progresión (rutas oficiales, etapa 2).
///
/// El mapa deja de ser el camino de niveles por XP (SCRUM-226) y pasa a ser
/// el de las rutas oficiales del administrador. Los niveles siguen en Tu
/// progresión. La pantalla se monta sola: la barra inferior la pone el
/// router, no ella.
void main() {
  final estadio = rutaDePrueba(
    id: 'ruta-estadio',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    distanciaKm: 5.23,
    dificultad: Dificultad.facil,
  );
  final nutibara = rutaDePrueba(
    id: 'ruta-nutibara',
    nombre: 'Cerro Nutibara',
    estado: EstadoRuta.publicada,
    distanciaKm: 7.5,
    dificultad: Dificultad.dificil,
  );
  // Sin dificultad: un Runner Experto todavía no la clasificó.
  final rio = rutaDePrueba(
    id: 'ruta-rio',
    nombre: 'Parque del río',
    estado: EstadoRuta.publicada,
    distanciaKm: 3,
  );
  // Sin distancia: el entrenamiento del que salió no la guardó.
  final laureles = rutaDePrueba(
    id: 'ruta-laureles',
    nombre: 'Ciclovía de Laureles',
    estado: EstadoRuta.publicada,
    distanciaKm: null,
    dificultad: Dificultad.moderada,
  );

  late RutasOficialesRepositorioFalso repositorio;

  /// Abre el mapa con las rutas [oficiales] en ese orden y las [completadas]
  /// del corredor. Al lado va el detalle de ruta, para ver a dónde lleva
  /// tocar una parada.
  Future<GoRouter> abrirMapa(
    WidgetTester tester, {
    List<Ruta>? oficiales,
    Set<String> completadas = const {},
    Object? errorAlListar,
    Object? errorAlLeerCompletadas,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio =
        RutasOficialesRepositorioFalso(
            oficiales: oficiales ?? [estadio, nutibara, rio],
            completadasPorMi: completadas,
          )
          ..errorAlListar = errorAlListar
          ..errorAlLeerCompletadas = errorAlLeerCompletadas;

    final router = GoRouter(
      initialLocation: MapaProgresionScreen.ruta,
      routes: [
        GoRoute(
          path: MapaProgresionScreen.ruta,
          builder: (_, _) => const MapaProgresionScreen(),
        ),
        GoRoute(
          path: DetalleRutaScreen.ruta,
          builder: (_, state) =>
              Scaffold(body: Text('Detalle ${state.pathParameters['rutaId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    // Solo las rutas oficiales: si el mapa todavía leyera los niveles o la
    // XP, iría a Supabase, que aquí no existe, y la prueba lo notaría.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasOficialesRepositoryProvider.overrideWithValue(repositorio),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  final marcador = find.byKey(CaminoProgresion.claveMarcador);

  Finder parada(String rutaId) =>
      find.byKey(CaminoProgresion.claveParada(rutaId));

  Finder dentroDe(Finder contenedor, Finder buscado) =>
      find.descendant(of: contenedor, matching: buscado);

  Finder enLaParada(String rutaId, String fragmento) =>
      dentroDe(parada(rutaId), find.textContaining(fragmento));

  Finder estadoDe(String rutaId, String estado) =>
      dentroDe(parada(rutaId), find.text(estado));

  Finder marcadorEn(String rutaId) => dentroDe(parada(rutaId), marcador);

  bool vaAntes(WidgetTester tester, String arriba, String abajo) =>
      tester.getTopLeft(parada(arriba)).dy <
      tester.getTopLeft(parada(abajo)).dy;

  Future<void> refrescar(WidgetTester tester) async {
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tiene el título "Mapa de progresión"', (tester) async {
    await abrirMapa(tester);

    expect(find.text('Mapa de progresión'), findsOneWidget);
  });

  group('criterio 1: las rutas oficiales en el orden del administrador', () {
    testWidgets('muestra cada ruta con su nombre, distancia y dificultad, en '
        'el orden del camino', (tester) async {
      await abrirMapa(tester);

      expect(find.byType(CaminoProgresion), findsOneWidget);
      expect(enLaParada('ruta-estadio', 'Vuelta al estadio'), findsOneWidget);
      expect(enLaParada('ruta-estadio', '5.23 km'), findsOneWidget);
      expect(enLaParada('ruta-estadio', 'Fácil'), findsOneWidget);
      expect(enLaParada('ruta-nutibara', 'Cerro Nutibara'), findsOneWidget);
      expect(enLaParada('ruta-nutibara', '7.5 km'), findsOneWidget);
      expect(enLaParada('ruta-nutibara', 'Difícil'), findsOneWidget);
      expect(enLaParada('ruta-rio', 'Parque del río'), findsOneWidget);
      expect(enLaParada('ruta-rio', '3 km'), findsOneWidget);

      expect(vaAntes(tester, 'ruta-estadio', 'ruta-nutibara'), isTrue);
      expect(vaAntes(tester, 'ruta-nutibara', 'ruta-rio'), isTrue);
    });

    testWidgets('sin dificultad dice "Sin clasificar" y sin distancia lo '
        'avisa', (tester) async {
      await abrirMapa(tester, oficiales: [rio, laureles]);

      expect(
        enLaParada('ruta-rio', TarjetaRutaExplorar.sinDificultad),
        findsOneWidget,
      );
      expect(
        enLaParada('ruta-laureles', TarjetaRuta.sinDistancia),
        findsOneWidget,
      );
      expect(enLaParada('ruta-laureles', 'Moderada'), findsOneWidget);
    });

    testWidgets('ya no es el camino de niveles: no habla de XP', (
      tester,
    ) async {
      await abrirMapa(tester, completadas: {'ruta-estadio'});

      expect(find.textContaining('XP'), findsNothing);
      expect(find.text('Todavía no hay niveles'), findsNothing);
    });
  });

  group('criterio 2: el estado de cada parada', () {
    testWidgets('completada, siguiente o bloqueada según lo que corrió', (
      tester,
    ) async {
      await abrirMapa(tester, completadas: {'ruta-estadio'});

      expect(estadoDe('ruta-estadio', 'Completada'), findsOneWidget);
      expect(estadoDe('ruta-nutibara', 'Siguiente'), findsOneWidget);
      expect(estadoDe('ruta-rio', 'Bloqueada'), findsOneWidget);
    });

    testWidgets('sin ninguna completada, la primera es la siguiente y las '
        'demás están bloqueadas', (tester) async {
      await abrirMapa(tester);

      expect(estadoDe('ruta-estadio', 'Siguiente'), findsOneWidget);
      expect(estadoDe('ruta-nutibara', 'Bloqueada'), findsOneWidget);
      expect(estadoDe('ruta-rio', 'Bloqueada'), findsOneWidget);
      expect(find.text('Completada'), findsNothing);
    });
  });

  group('criterio 3: el marcador y el encabezado', () {
    testWidgets('el marcador está en la siguiente y el encabezado la '
        'nombra', (tester) async {
      await abrirMapa(tester, completadas: {'ruta-estadio'});

      expect(marcador, findsOneWidget);
      expect(marcadorEn('ruta-nutibara'), findsOneWidget);
      expect(find.text('Siguiente: Cerro Nutibara'), findsOneWidget);
      expect(find.text('1 de 3 rutas completadas'), findsOneWidget);
      expect(find.text('¡Completaste el camino!'), findsNothing);
    });

    testWidgets('sin ninguna completada, va en la primera y lleva 0 de '
        'todas', (tester) async {
      await abrirMapa(tester);

      expect(marcadorEn('ruta-estadio'), findsOneWidget);
      expect(find.text('Siguiente: Vuelta al estadio'), findsOneWidget);
      expect(find.text('0 de 3 rutas completadas'), findsOneWidget);
    });

    testWidgets('si las completó todas, el marcador está en la última y dice '
        '"¡Completaste el camino!"', (tester) async {
      await abrirMapa(
        tester,
        completadas: {'ruta-estadio', 'ruta-nutibara', 'ruta-rio'},
      );

      expect(marcadorEn('ruta-rio'), findsOneWidget);
      expect(find.text('¡Completaste el camino!'), findsOneWidget);
      expect(find.textContaining('Siguiente:'), findsNothing);
      expect(find.text('3 de 3 rutas completadas'), findsOneWidget);
    });

    testWidgets('con una sola ruta, el conteo dice "1 de 1"', (tester) async {
      await abrirMapa(
        tester,
        oficiales: [estadio],
        completadas: {'ruta-estadio'},
      );

      expect(find.text('¡Completaste el camino!'), findsOneWidget);
      expect(find.text('1 de 1 rutas completadas'), findsOneWidget);
      expect(marcadorEn('ruta-estadio'), findsOneWidget);
    });

    testWidgets('un nombre largo en el encabezado no desborda en 320x568', (
      tester,
    ) async {
      final larga = rutaDePrueba(
        id: 'ruta-larga',
        nombre:
            'Circuito universitario de la Universidad de Medellín y '
            'regreso por la avenida 80',
        estado: EstadoRuta.publicada,
        distanciaKm: 21.0975,
        dificultad: Dificultad.moderada,
      );
      await abrirMapa(
        tester,
        oficiales: [larga, estadio],
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Siguiente: Circuito'), findsOneWidget);
      expect(marcadorEn('ruta-larga'), findsOneWidget);
    });
  });

  group('criterio 4: una ruta completada fuera de orden', () {
    testWidgets('sale completada, pero el marcador sigue en la primera que '
        'falta', (tester) async {
      await abrirMapa(tester, completadas: {'ruta-rio'});

      expect(estadoDe('ruta-rio', 'Completada'), findsOneWidget);
      expect(estadoDe('ruta-estadio', 'Siguiente'), findsOneWidget);
      expect(estadoDe('ruta-nutibara', 'Bloqueada'), findsOneWidget);
      expect(marcadorEn('ruta-estadio'), findsOneWidget);
      expect(marcadorEn('ruta-rio'), findsNothing);
      expect(find.text('Siguiente: Vuelta al estadio'), findsOneWidget);
      expect(find.text('1 de 3 rutas completadas'), findsOneWidget);
    });
  });

  group('criterio 5: sale de lo completado, no de posiciones guardadas', () {
    testWidgets('si el administrador reordena, al volver a consultar el mapa '
        'se recalcula y nadie pierde lo corrido', (tester) async {
      await abrirMapa(tester, completadas: {'ruta-estadio'});
      expect(find.text('Siguiente: Cerro Nutibara'), findsOneWidget);

      // El administrador sube el río al principio del camino.
      await repositorio.mover('ruta-rio', 1);
      await refrescar(tester);

      expect(vaAntes(tester, 'ruta-rio', 'ruta-estadio'), isTrue);
      expect(vaAntes(tester, 'ruta-estadio', 'ruta-nutibara'), isTrue);
      expect(estadoDe('ruta-estadio', 'Completada'), findsOneWidget);
      expect(estadoDe('ruta-rio', 'Siguiente'), findsOneWidget);
      expect(estadoDe('ruta-nutibara', 'Bloqueada'), findsOneWidget);
      expect(marcadorEn('ruta-rio'), findsOneWidget);
      expect(find.text('Siguiente: Parque del río'), findsOneWidget);
      expect(find.text('1 de 3 rutas completadas'), findsOneWidget);
    });

    testWidgets('las completadas que ya no son oficiales no entran en el '
        'conteo', (tester) async {
      await abrirMapa(
        tester,
        completadas: {'ruta-estadio', 'ruta-retirada-del-mapa'},
      );

      expect(find.text('1 de 3 rutas completadas'), findsOneWidget);
      expect(parada('ruta-retirada-del-mapa'), findsNothing);
      expect(find.text('Siguiente: Cerro Nutibara'), findsOneWidget);
    });

    testWidgets('al refrescar vuelve a leer las completadas y el marcador '
        'avanza', (tester) async {
      await abrirMapa(tester, completadas: {'ruta-estadio'});
      expect(marcadorEn('ruta-nutibara'), findsOneWidget);
      final consultasAntes = repositorio.consultasCompletadas;

      // Lo que en la etapa 4 hará el cierre de un entrenamiento.
      repositorio.completadasPorMi.add('ruta-nutibara');
      await refrescar(tester);

      expect(repositorio.consultasCompletadas, greaterThan(consultasAntes));
      expect(marcadorEn('ruta-rio'), findsOneWidget);
      expect(marcadorEn('ruta-nutibara'), findsNothing);
      expect(find.text('2 de 3 rutas completadas'), findsOneWidget);
    });
  });

  group('criterio 6: tocar una parada', () {
    testWidgets('abre el detalle de su ruta encima del mapa', (tester) async {
      final router = await abrirMapa(tester, completadas: {'ruta-estadio'});

      await tester.tap(parada('ruta-nutibara'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle ruta-nutibara'), findsOneWidget);
      // Con `push`, la uri de la lista sigue siendo la del mapa: lo apilado
      // es la última coincidencia.
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        DetalleRutaScreen.rutaDe('ruta-nutibara'),
      );
      // `push`: el mapa sigue debajo y se vuelve a él.
      expect(router.routerDelegate.currentConfiguration.matches.length, 2);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(CaminoProgresion), findsOneWidget);
    });

    testWidgets('una completada y una bloqueada también abren su detalle', (
      tester,
    ) async {
      for (final id in ['ruta-estadio', 'ruta-rio']) {
        await abrirMapa(tester, completadas: {'ruta-estadio'});

        await tester.tap(parada(id));
        await tester.pumpAndSettle();

        expect(find.text('Detalle $id'), findsOneWidget, reason: id);
      }
    });
  });

  group('criterio 7: sin rutas oficiales', () {
    testWidgets('muestra el aviso, sin camino ni marcador', (tester) async {
      await abrirMapa(tester, oficiales: const []);

      expect(find.text('Todavía no hay rutas oficiales'), findsOneWidget);
      expect(
        find.text('Cuando el administrador las elija, verás tu camino aquí.'),
        findsOneWidget,
      );
      expect(find.byType(CaminoProgresion), findsNothing);
      expect(marcador, findsNothing);
      expect(find.textContaining('Siguiente:'), findsNothing);
      // Sin camino no hay nada que terminar.
      expect(find.text('¡Completaste el camino!'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aunque el corredor tenga completadas de antes', (
      tester,
    ) async {
      await abrirMapa(
        tester,
        oficiales: const [],
        completadas: {'ruta-retirada-del-mapa'},
      );

      expect(find.text('Todavía no hay rutas oficiales'), findsOneWidget);
      expect(marcador, findsNothing);
      expect(find.text('¡Completaste el camino!'), findsNothing);
    });
  });

  group('si no carga', () {
    testWidgets('si fallan las rutas oficiales, avisa y "Reintentar" vuelve '
        'a consultar y muestra el mapa', (tester) async {
      await abrirMapa(
        tester,
        errorAlListar: StateError('PostgrestException: permission denied'),
      );

      expect(
        find.text('No pudimos cargar tu mapa de progresión'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(marcador, findsNothing);
      expect(repositorio.consultas, 1);

      repositorio.errorAlListar = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(repositorio.consultas, 2);
      expect(
        find.text('No pudimos cargar tu mapa de progresión'),
        findsNothing,
      );
      expect(marcadorEn('ruta-estadio'), findsOneWidget);
    });

    testWidgets('si fallan las completadas también avisa y permite '
        'reintentar', (tester) async {
      await abrirMapa(
        tester,
        completadas: {'ruta-estadio'},
        errorAlLeerCompletadas: StateError('sin conexión'),
      );

      expect(
        find.text('No pudimos cargar tu mapa de progresión'),
        findsOneWidget,
      );
      // Sin las completadas no se sabe dónde va: no se dibuja un camino a
      // medias que diga que no ha corrido nada.
      expect(find.byType(CaminoProgresion), findsNothing);
      expect(find.textContaining('sin conexión'), findsNothing);

      repositorio.errorAlLeerCompletadas = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(CaminoProgresion), findsOneWidget);
      expect(marcadorEn('ruta-nutibara'), findsOneWidget);
    });

    testWidgets('nunca muestra el mensaje técnico del error', (tester) async {
      await abrirMapa(
        tester,
        errorAlListar: StateError('PostgrestException: permission denied'),
      );

      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.textContaining('permission denied'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });
  });

  test('la ruta de la pantalla es la de la pestaña Progreso', () {
    // Si una cambia sin la otra, la pestaña llevaría a ninguna parte.
    expect(MapaProgresionScreen.ruta, SeccionPrincipal.progreso.ruta);
  });
}
