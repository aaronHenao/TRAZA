import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/publicar_ruta_screen.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/trazado_recorrido.dart';

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
