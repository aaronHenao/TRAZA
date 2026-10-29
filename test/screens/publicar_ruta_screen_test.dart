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

  /// ~1,1 km en línea recta, con un punto cada ~11 m. Tiene que ser bastante
  /// más largo que los dos radios de privacidad (RNF-04) o la pantalla diría
  /// que no queda trazo que publicar.
  final recorrido = [
    for (var i = 0; i <= 100; i++) punto(6.2442 + i / 10000, -75.5812),
  ];

  /// Un recorrido de ~330 m: entero dentro de los dos círculos de privacidad.
  final recorridoCorto = [
    for (var i = 0; i <= 30; i++) punto(6.2442 + i / 10000, -75.5812),
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

  /// Enciende "Mostrar el recorrido completo" (RNF-04).
  ///
  /// Hay que desplazarse hasta el interruptor y centrarlo: tras el
  /// desplazamiento queda al borde de la pantalla y el toque no lo alcanza.
  Future<void> encenderRecorridoCompleto(WidgetTester tester) async {
    final interruptor = find.byKey(PublicarRutaScreen.claveRecorridoCompleto);
    await tester.scrollUntilVisible(
      interruptor,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(interruptor);
    await tester.pumpAndSettle();
    await tester.tap(interruptor);
    await tester.pumpAndSettle();
  }

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
      final lista = find.byType(Scrollable).first;

      // RNF-04: antes de publicar se le dice qué no se publica.
      final aviso = find.byKey(PublicarRutaScreen.claveAvisoPrivacidad);
      await tester.scrollUntilVisible(aviso, 200, scrollable: lista);
      expect(find.textContaining('no publicamos los primeros'), findsOneWidget);
      expect(find.textContaining('200 m'), findsOneWidget);
      // Y que la distancia mostrada sigue siendo la que corrió.
      expect(
        find.textContaining('la distancia que se muestra sigue siendo'),
        findsOneWidget,
      );

      // SCRUM-321: dos revisiones, primero el administrador.
      final revision = find.textContaining(
        'El administrador y después un Runner Experto revisan tu ruta',
      );
      await tester.scrollUntilVisible(revision, 200, scrollable: lista);
      expect(revision, findsOneWidget);
    });

    testWidgets('el interruptor del recorrido completo viene apagado '
        '(RNF-04)', (tester) async {
      await _abrir(tester, resumen: resumen());

      final interruptor = find.byKey(PublicarRutaScreen.claveRecorridoCompleto);
      await tester.scrollUntilVisible(
        interruptor,
        200,
        scrollable: find.byType(Scrollable).first,
      );

      // La privacidad no se pide, se da.
      expect(tester.widget<SwitchListTile>(interruptor).value, isFalse);
      expect(
        find.text('Mostrar el recorrido completo (incluye mi inicio y fin)'),
        findsOneWidget,
      );
    });

    testWidgets('al encenderlo, el aviso advierte en vez de explicar '
        '(RNF-04)', (tester) async {
      await _abrir(tester, resumen: resumen());

      await encenderRecorridoCompleto(tester);

      expect(
        find.textContaining('cualquiera que vea tu ruta sabrá dónde empieza'),
        findsOneWidget,
      );
      expect(find.textContaining('tu casa o tu trabajo'), findsOneWidget);
      // Y deja de decir que no se publican los extremos.
      expect(find.textContaining('no publicamos los primeros'), findsNothing);
    });

    testWidgets('encendido manda el recorrido entero (RNF-04)', (tester) async {
      final repositorio = await _abrir(tester, resumen: resumen());

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta al estadio',
      );
      await encenderRecorridoCompleto(tester);
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      final enviada = repositorio.recibida!;
      expect(enviada.recorridoCompleto, isTrue);
      expect(enviada.trazado.length, recorrido.length);
      expect(enviada.trazado.first.latitud, recorrido.first.latitud);
    });

    testWidgets('una ruta corta sí se puede publicar entera (RNF-04)', (
      tester,
    ) async {
      final repositorio = await _abrir(
        tester,
        resumen: resumen(puntos: recorridoCorto),
      );

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta corta',
      );
      await encenderRecorridoCompleto(tester);
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(repositorio.recibida, isNotNull);
      expect(repositorio.recibida!.recorridoCompleto, isTrue);
    });

    testWidgets('un recorrido más corto que los dos radios no se puede '
        'publicar y dice por qué (RNF-04)', (tester) async {
      final repositorio = await _abrir(
        tester,
        resumen: resumen(puntos: recorridoCorto),
      );

      await tester.enterText(
        find.byKey(PublicarRutaScreen.claveNombre),
        'Vuelta corta',
      );
      await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no publicamos los primeros ni los últimos 200 m'),
        findsWidgets,
      );
      expect(
        find.textContaining('Publica un entrenamiento más largo'),
        findsOneWidget,
      );
      expect(repositorio.creaciones, 0);
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
      // Menos puntos que el recorrido: los extremos privados no se mandan
      // (RNF-04).
      expect(enviada.trazado.length, lessThan(recorrido.length));
      expect(enviada.trazado.first.latitud, isNot(recorrido.first.latitud));
      expect(enviada.trazado.last.latitud, isNot(recorrido.last.latitud));

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

    testWidgets('aprobada por el administrador sigue en revision '
        '(SCRUM-321)', (tester) async {
      await _abrir(
        tester,
        resumen: resumen(),
        existente: rutaDePrueba(
          nombre: 'Vuelta al estadio',
          estado: EstadoRuta.revisionExperto,
        ),
      );

      expect(find.text('Esta ruta está en revisión'), findsOneWidget);
      expect(find.text('Ya publicaste esta ruta'), findsNothing);
      expect(
        find.textContaining('Pendiente de revisión del Runner Experto'),
        findsOneWidget,
      );
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

    testWidgets('ya enviada, la tarjeta dice que espera al administrador '
        '(SCRUM-321, criterio 1 de SCRUM-363)', (tester) async {
      await _abrirConMiRuta(tester, resumen: resumen(), ruta: rutaDePrueba());

      expect(
        _enLaTarjeta('Pendiente de revisión del administrador'),
        findsOneWidget,
      );
      expect(find.byKey(PublicarRutaScreen.claveNombre), findsNothing);
    });

    testWidgets('aprobada por el administrador, la tarjeta dice que espera '
        'al Runner Experto, no que ya está publicada (criterio 1 de '
        'SCRUM-363)', (tester) async {
      await _abrirConMiRuta(
        tester,
        resumen: resumen(),
        ruta: rutaDePrueba(estado: EstadoRuta.revisionExperto),
      );

      expect(
        _enLaTarjeta('Pendiente de revisión del Runner Experto'),
        findsOneWidget,
      );
      expect(_enLaTarjeta(EstadoRuta.publicada.etiqueta), findsNothing);
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
