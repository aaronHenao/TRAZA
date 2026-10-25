import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/publicar_ruta_screen.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/trazado_recorrido.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/roles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas del formulario para publicar una ruta (SCRUM-241): lo que muestra
/// del recorrido, la validación antes de enviar (criterio 3) y el aviso de
/// que queda en revisión (criterio 1).
void main() {
  PuntoGps punto(double lat, double lng) => PuntoGps(
    latitud: lat,
    longitud: lng,
    capturadoEn: DateTime(2026, 10, 17, 7),
  );

  final recorrido = [
    punto(6.2442, -75.5812),
    punto(6.2450, -75.5800),
    punto(6.2461, -75.5795),
  ];

  ResumenEntrenamiento resumen({
    String? entrenamientoId = 'e-123',
    double? distanciaMetros = 5230.5,
    List<PuntoGps>? puntos,
  }) => ResumenEntrenamiento(
    entrenamientoId: entrenamientoId,
    nombreActividad: 'Trote',
    fechaFin: DateTime(2026, 10, 17, 8),
    duracion: const Duration(minutes: 32),
    distanciaMetros: distanciaMetros,
    puntos: puntos ?? recorrido,
  );

  group('lo que se publica', () {
    testWidgets('muestra el trazado, la distancia y el aviso de revision', (
      tester,
    ) async {
      await _abrir(tester, resumen: resumen());

      expect(find.text('Publicar ruta'), findsWidgets);
      expect(find.byType(TrazadoRecorrido), findsOneWidget);
      expect(
        find.text('5.23 km · la distancia que llevará tu ruta'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Un Runner Experto revisa tu ruta'),
        findsOneWidget,
      );
    });

    testWidgets('un entrenamiento sin distancia lo dice (SCRUM-240)', (
      tester,
    ) async {
      await _abrir(tester, resumen: resumen(distanciaMetros: null));

      expect(
        find.text('Este entrenamiento no registró distancia'),
        findsOneWidget,
      );
    });

    testWidgets('sin entrenamiento no hay nada que publicar', (tester) async {
      // Alguien que llega escribiendo la dirección.
      await _abrir(tester, resumen: null);

      expect(find.text('No hay recorrido que publicar'), findsOneWidget);
      expect(find.byKey(PublicarRutaScreen.clavePublicar), findsNothing);
    });
  });

  group('validacion antes de enviar (criterio 3)', () {
    testWidgets('sin nombre marca el campo y no toca la base', (tester) async {
      final repositorio = await _abrir(tester, resumen: resumen());

      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(find.text('Ponle un nombre a tu ruta.'), findsOneWidget);
      expect(find.text(PublicarRutaScreen.revisaLosCampos), findsOneWidget);
      expect(repositorio.creaciones, 0);
    });

    testWidgets('el error se va en cuanto se escribe', (tester) async {
      await _abrir(tester, resumen: resumen());

      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();
      expect(find.text('Ponle un nombre a tu ruta.'), findsOneWidget);

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta al estadio',
      );
      await tester.pumpAndSettle();

      expect(find.text('Ponle un nombre a tu ruta.'), findsNothing);
    });

    testWidgets('un entrenamiento sin recorrido no se puede publicar', (
      tester,
    ) async {
      final repositorio = await _abrir(
        tester,
        resumen: resumen(puntos: [punto(6.2442, -75.5812)]),
      );

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Un solo punto',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(
        find.text('Este entrenamiento no tiene un recorrido que publicar.'),
        findsOneWidget,
      );
      expect(repositorio.creaciones, 0);
    });
  });

  group('publicar deja la ruta en revision (criterio 1)', () {
    testWidgets('manda el recorrido y avisa que queda en revision', (
      tester,
    ) async {
      final repositorio = await _abrir(tester, resumen: resumen());

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        '  Vuelta al estadio  ',
      );
      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveDescripcion),
        'Plana y con sombra',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      final enviada = repositorio.recibida!;
      expect(enviada.entrenamientoId, 'e-123');
      expect(enviada.nombre, 'Vuelta al estadio');
      expect(enviada.descripcion, 'Plana y con sombra');
      expect(enviada.trazado.length, recorrido.length);

      // Vuelve al resumen y el aviso sigue a la vista.
      expect(find.text('Pantalla de resumen'), findsOneWidget);
      expect(find.text(PublicacionRuta.enRevision), findsOneWidget);
    });

    testWidgets('si falla no se pierde lo escrito', (tester) async {
      final repositorio = await _abrir(
        tester,
        resumen: resumen(),
        error: StateError('sin red'),
      );

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta al estadio',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(find.text(PublicacionRuta.noSePudo), findsOneWidget);
      expect(repositorio.creaciones, 1);
      // Sigue en el formulario, con el nombre puesto.
      expect(find.text('Vuelta al estadio'), findsOneWidget);
      expect(find.byKey(PublicarRutaScreen.clavePublicar), findsOneWidget);
    });

    testWidgets('el doble envio lo cuenta la base, no la pantalla', (
      tester,
    ) async {
      // 23505: el índice único de 0031 lo impide y el mensaje lo explica.
      final repositorio = await _abrir(
        tester,
        resumen: resumen(),
        error: const EntrenamientoYaPublicadoException(),
      );

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta al estadio',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(find.text(PublicacionRuta.yaPublicada), findsOneWidget);
      expect(repositorio.creaciones, 1);
    });

    testWidgets('un entrenamiento ajeno o sin terminar no se publica', (
      tester,
    ) async {
      await _abrir(
        tester,
        resumen: resumen(),
        error: const EntrenamientoNoPublicableException(),
      );

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta al estadio',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(find.text(PublicacionRuta.noPublicable), findsOneWidget);
    });
  });

  group('un entrenamiento ya publicado', () {
    testWidgets('en revision: lo dice y no ofrece el formulario', (
      tester,
    ) async {
      await _abrir(
        tester,
        resumen: resumen(),
        existente: rutaDePrueba(nombre: 'Vuelta al estadio'),
      );

      expect(find.byKey(PublicarRutaScreen.claveYaPublicada), findsOneWidget);
      expect(find.text('Esta ruta está en revisión'), findsOneWidget);
      expect(find.byKey(PublicarRutaScreen.claveNombre), findsNothing);
    });

    testWidgets('aguanta el nombre mas largo que admite la tabla', (
      tester,
    ) async {
      await _abrir(
        tester,
        resumen: resumen(),
        existente: rutaDePrueba(nombre: 'R' * 120),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('ya publicada: lo dice con su nombre', (tester) async {
      await _abrir(
        tester,
        resumen: resumen(),
        existente: rutaDePrueba(
          nombre: 'Cerro Pan de Azúcar',
          estado: EstadoRuta.publicada,
          fechaPublicacion: DateTime(2026, 10, 18),
        ),
      );

      expect(find.text('Ya publicaste esta ruta'), findsOneWidget);
      expect(find.textContaining('Cerro Pan de Azúcar'), findsOneWidget);
    });

    testWidgets('se pregunta al abrir, antes de escribir nada', (tester) async {
      final repositorio = await _abrir(tester, resumen: resumen());

      expect(repositorio.consultasDeEntrenamiento, 1);
    });
  });

  group('la clasificación por un Runner Experto (SCRUM-363)', () {
    Future<void> publicar(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta al estadio',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();
    }

    testWidgets('con la distancia registrada, al publicar avisa que quedó '
        'pendiente de revisión por un Runner Experto (criterio 1 de '
        'SCRUM-363)', (tester) async {
      final repositorio = await _abrir(tester, resumen: resumen());

      await publicar(tester);

      expect(find.text(PublicacionRuta.enRevision), findsOneWidget);
      expect(find.textContaining('pendiente de revisión'), findsOneWidget);
      expect(repositorio.rutas.single.estado, EstadoRuta.enRevision);
      expect(find.text('Pantalla de resumen'), findsOneWidget);
    });

    testWidgets('sin la distancia registrada informa que no puede '
        'clasificarse y que quedó con la dificultad pendiente (criterio 3 de '
        'SCRUM-363)', (tester) async {
      final repositorio = await _abrir(
        tester,
        resumen: resumen(distanciaMetros: null),
      );
      // La base no le encuentra distancia al entrenamiento.
      repositorio.distanciaNueva = null;

      await publicar(tester);

      expect(find.text(PublicacionRuta.sinDatosParaClasificar), findsOneWidget);
      expect(find.text(PublicacionRuta.enRevision), findsNothing);
      // Quedó registrada: no hay nada que reintentar en el formulario.
      expect(repositorio.creaciones, 1);
      expect(repositorio.rutas.single.estado, EstadoRuta.datosIncompletos);
      expect(find.text('Pantalla de resumen'), findsOneWidget);
    });

    testWidgets('ya enviada y en revisión, la tarjeta dice "Pendiente de '
        'revisión" (criterio 1 de SCRUM-363)', (tester) async {
      await _abrirConMiRuta(tester, resumen: resumen(), ruta: rutaDePrueba());

      expect(_enLaTarjeta('Pendiente de revisión'), findsOneWidget);
      expect(find.byKey(PublicarRutaScreen.claveNombre), findsNothing);
    });

    testWidgets('ya clasificada, la tarjeta dice "Lista para publicar" y '
        'lleva a la ruta para confirmarla (criterio 2 de SCRUM-363)', (
      tester,
    ) async {
      await _abrirConMiRuta(
        tester,
        resumen: resumen(),
        ruta: rutaDePrueba(
          estado: EstadoRuta.clasificada,
          dificultad: Dificultad.moderada,
        ),
      );

      expect(_enLaTarjeta('Lista para publicar'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(PublicarRutaScreen.claveVerRuta),
          matching: find.text('Ver mi ruta'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(PublicarRutaScreen.claveVerRuta));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsOneWidget);
      expect(find.byKey(DetalleRutaScreen.clavePublicar), findsOneWidget);
    });

    testWidgets('al volver de publicarla desde su detalle, la tarjeta ya dice '
        'que está publicada (criterio 2 de SCRUM-363)', (tester) async {
      await _abrirConMiRuta(
        tester,
        resumen: resumen(),
        ruta: rutaDePrueba(
          estado: EstadoRuta.clasificada,
          dificultad: Dificultad.moderada,
        ),
      );

      await tester.tap(find.byKey(PublicarRutaScreen.claveVerRuta));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(DetalleRutaScreen.clavePublicar));
      await tester.tap(find.byKey(DetalleRutaScreen.clavePublicar));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(_enLaTarjeta('Publicada'), findsOneWidget);
      expect(_enLaTarjeta('Ya publicaste esta ruta'), findsOneWidget);
      expect(_enLaTarjeta('Lista para publicar'), findsNothing);
    });

    testWidgets('sin la distancia, la tarjeta dice "Dificultad pendiente" '
        '(criterio 3 de SCRUM-363)', (tester) async {
      await _abrirConMiRuta(
        tester,
        resumen: resumen(distanciaMetros: null),
        ruta: rutaDePrueba(
          estado: EstadoRuta.datosIncompletos,
          distanciaKm: null,
        ),
      );

      expect(_enLaTarjeta('Dificultad pendiente'), findsOneWidget);

      await tester.tap(find.byKey(PublicarRutaScreen.claveVerRuta));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsOneWidget);
    });
  });
}

/// [texto] dentro de la tarjeta del entrenamiento ya publicado.
Finder _enLaTarjeta(String texto) => find.descendant(
  of: find.byKey(PublicarRutaScreen.claveYaPublicada),
  matching: find.text(texto),
);

/// Abre el formulario de un entrenamiento que ya tiene [ruta], con el
/// detalle detrás de "Ver mi ruta" y la sesión de su autor (SCRUM-363).
Future<RutasRepositorioFalso> _abrirConMiRuta(
  WidgetTester tester, {
  required ResumenEntrenamiento resumen,
  required Ruta ruta,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = RutasRepositorioFalso(
    existente: ruta,
    rutas: [ruta],
    usuario: ruta.autorId,
  );

  final router = GoRouter(
    initialLocation: '/resumen',
    routes: [
      GoRoute(
        path: '/resumen',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de resumen')),
      ),
      GoRoute(
        path: PublicarRutaScreen.ruta,
        builder: (_, estado) =>
            PublicarRutaScreen(resumen: estado.extra as ResumenEntrenamiento?),
      ),
      GoRoute(
        path: DetalleRutaScreen.ruta,
        builder: (_, estado) => DetalleRutaScreen(
          rutaId: estado.pathParameters['rutaId']!,
          vistaPrevia: estado.extra as Ruta?,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rutasRepositoryProvider.overrideWithValue(repositorio),
        usuarioActualProvider.overrideWithValue(() => ruta.autorId),
        rolesRepositoryProvider.overrideWithValue(RolesFalso()),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 12)),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  router.push(PublicarRutaScreen.ruta, extra: resumen);
  await tester.pumpAndSettle();

  return repositorio;
}

/// Abre el formulario como lo abre el resumen: con `push` y el entrenamiento
/// en `extra`, para que al publicar pueda volver.
Future<RutasRepositorioFalso> _abrir(
  WidgetTester tester, {
  required ResumenEntrenamiento? resumen,
  Object? error,
  Ruta? existente,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = RutasRepositorioFalso(error: error, existente: existente);

  final router = GoRouter(
    initialLocation: '/resumen',
    routes: [
      GoRoute(
        path: '/resumen',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de resumen')),
      ),
      GoRoute(
        path: PublicarRutaScreen.ruta,
        builder: (_, estado) =>
            PublicarRutaScreen(resumen: estado.extra as ResumenEntrenamiento?),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [rutasRepositoryProvider.overrideWithValue(repositorio)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  router.push(PublicarRutaScreen.ruta, extra: resumen);
  await tester.pumpAndSettle();

  return repositorio;
}
