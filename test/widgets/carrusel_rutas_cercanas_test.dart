import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/services/inicio_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/carrusel_rutas_cercanas.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';

import '../utiles/rutas_repository_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas del carrusel de rutas de la portada (SCRUM-289).
///
/// Es el criterio 4 de SCRUM-283: las rutas de lado, con su dificultad y su
/// distancia, y "Ver todas" hacia la sección de Rutas.
void main() {
  Ruta publicada({
    String id = 'r-1',
    String nombre = 'Vuelta al estadio',
    double? distanciaKm = 5.23,
  }) => rutaDePrueba(
    id: id,
    nombre: nombre,
    distanciaKm: distanciaKm,
    estado: EstadoRuta.publicada,
    fechaPublicacion: DateTime(2026, 10, 18, 9),
  );

  late _MockPermisosService permisos;

  setUp(() {
    permisos = _MockPermisosService();
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  Future<GoRouter> montar(
    WidgetTester tester, {
    List<Ruta>? rutas,
    Object? error,
    EstadoPermiso ubicacion = EstadoPermiso.concedido,
    Size tamano = const Size(390, 844),
  }) async {
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => ubicacion);
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: CarruselRutasCercanas(),
            ),
          ),
        ),
        GoRoute(
          path: RutasScreen.ruta,
          builder: (_, _) => const Scaffold(body: Text('Sección de Rutas')),
        ),
        GoRoute(
          path: DetalleRutaScreen.ruta,
          builder: (_, state) =>
              Scaffold(body: Text('Detalle ${state.pathParameters['rutaId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasRepositoryProvider.overrideWithValue(
            RutasRepositorioFalso(rutas: rutas ?? [publicada()], error: error),
          ),
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _PermisosGuardadosFalso(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  group('lo que muestra cada ruta', () {
    testWidgets('su nombre, su dificultad y su distancia', (tester) async {
      await montar(tester);

      expect(find.text('RUTAS CERCANAS'), findsOneWidget);
      expect(find.byKey(CarruselRutasCercanas.clave), findsOneWidget);
      expect(find.text('Vuelta al estadio'), findsOneWidget);
      expect(find.text('5.23 km'), findsOneWidget);
      // La dificultad la asigna HU-34: hasta entonces, ninguna está
      // clasificada y la pastilla lo dice.
      expect(find.text(CarruselRutasCercanas.sinDificultad), findsOneWidget);
    });

    testWidgets('una ruta sin distancia lo dice como el listado', (
      tester,
    ) async {
      await montar(tester, rutas: [publicada(distanciaKm: null)]);

      expect(find.text(TarjetaRuta.sinDistancia), findsOneWidget);
    });

    testWidgets('se recorren de lado, no hacia abajo', (tester) async {
      await montar(
        tester,
        rutas: [
          publicada(id: 'r-1', nombre: 'Vuelta al estadio'),
          publicada(id: 'r-2', nombre: 'Subida a Nutibara'),
          publicada(id: 'r-3', nombre: 'Rio arriba'),
        ],
      );

      final lista = tester.widget<ListView>(
        find.descendant(
          of: find.byKey(CarruselRutasCercanas.clave),
          matching: find.byType(ListView),
        ),
      );
      expect(lista.scrollDirection, Axis.horizontal);

      // La primera se ve; la tercera está fuera de pantalla hasta arrastrar.
      expect(find.text('Vuelta al estadio'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Rio arriba'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Rio arriba'), findsOneWidget);
    });

    testWidgets('asoma solo las primeras, no todas las publicadas', (
      tester,
    ) async {
      await montar(
        tester,
        rutas: [
          for (var i = 0; i < cuantasRutasEnPortada + 3; i++)
            publicada(id: 'r-$i', nombre: 'Ruta $i'),
        ],
      );

      final lista = tester.widget<ListView>(
        find.descendant(
          of: find.byKey(CarruselRutasCercanas.clave),
          matching: find.byType(ListView),
        ),
      );
      expect(lista.semanticChildCount, cuantasRutasEnPortada);
    });
  });

  group('a dónde lleva', () {
    testWidgets('"Ver todas" abre la sección de Rutas', (tester) async {
      final router = await montar(tester);

      await tester.tap(find.byKey(CarruselRutasCercanas.claveVerTodas));
      await tester.pumpAndSettle();

      expect(find.text('Sección de Rutas'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        RutasScreen.ruta,
      );
    });

    testWidgets('la sección reemplaza la portada: no se apila encima', (
      tester,
    ) async {
      final router = await montar(tester);

      await tester.tap(find.byKey(CarruselRutasCercanas.claveVerTodas));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.matches.length, 1);
    });

    testWidgets('tocar una ruta abre su detalle, de donde se puede volver', (
      tester,
    ) async {
      final router = await montar(tester);

      await tester.tap(find.text('Vuelta al estadio'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle r-1'), findsOneWidget);
      // `push`: la portada sigue debajo.
      expect(router.routerDelegate.currentConfiguration.matches.length, 2);
    });
  });

  group('cuando no hay rutas que mostrar', () {
    testWidgets('sin rutas publicadas lo explica y no ofrece "Ver todas"', (
      tester,
    ) async {
      await montar(tester, rutas: const []);

      expect(find.text('RUTAS CERCANAS'), findsOneWidget);
      expect(
        find.textContaining('Todavía no hay rutas publicadas'),
        findsOneWidget,
      );
      expect(find.byKey(CarruselRutasCercanas.claveVerTodas), findsNothing);
      expect(find.byKey(CarruselRutasCercanas.clave), findsNothing);
    });

    testWidgets('las que están en revisión no son de la comunidad', (
      tester,
    ) async {
      // Una ruta sin aprobar no se le muestra a nadie más que a su autor.
      await montar(tester, rutas: [rutaDePrueba(id: 'r-9')]);

      expect(
        find.textContaining('Todavía no hay rutas publicadas'),
        findsOneWidget,
      );
    });

    testWidgets('si no se pueden consultar, lo dice sin romper la portada', (
      tester,
    ) async {
      await montar(tester, error: Exception('sin red'));

      expect(
        find.textContaining('No pudimos cargar las rutas'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('sin permiso de ubicación (SCRUM-290)', () {
    testWidgets('explica para qué hace falta y ofrece concederlo', (
      tester,
    ) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      expect(find.text('RUTAS CERCANAS'), findsOneWidget);
      expect(find.byKey(CarruselRutasCercanas.claveSinPermiso), findsOneWidget);
      expect(
        find.text(CarruselRutasCercanas.porQueLaUbicacion),
        findsOneWidget,
      );
      expect(find.text('Aceptar'), findsOneWidget);
      // Ni rutas ni acceso a la sección mientras no se sepa qué está cerca.
      expect(find.byKey(CarruselRutasCercanas.clave), findsNothing);
      expect(find.byKey(CarruselRutasCercanas.claveVerTodas), findsNothing);
    });

    testWidgets('"Aceptar" pide el permiso al sistema', (tester) async {
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      await tester.tap(find.byKey(CarruselRutasCercanas.claveAceptarUbicacion));
      await tester.pumpAndSettle();

      verify(() => permisos.solicitarUbicacion()).called(1);
      // Concedido, el carrusel aparece solo.
      expect(find.text('Vuelta al estadio'), findsOneWidget);
      expect(find.byKey(CarruselRutasCercanas.claveVerTodas), findsOneWidget);
    });

    testWidgets('si lo negó para siempre, manda a los ajustes', (tester) async {
      await montar(tester, ubicacion: EstadoPermiso.bloqueado);

      expect(find.textContaining('ajustes del teléfono'), findsOneWidget);

      await tester.tap(find.byKey(CarruselRutasCercanas.claveAceptarUbicacion));
      await tester.pumpAndSettle();

      verify(() => permisos.abrirAjustes()).called(1);
      verifyNever(() => permisos.solicitarUbicacion());
    });

    testWidgets('con el permiso concedido no se pide nada', (tester) async {
      await montar(tester);

      expect(find.byKey(CarruselRutasCercanas.claveSinPermiso), findsNothing);
      expect(find.text('Aceptar'), findsNothing);
    });
  });

  testWidgets('en la pantalla más estrecha asoma la siguiente tarjeta', (
    tester,
  ) async {
    await montar(
      tester,
      rutas: [
        publicada(id: 'r-1', nombre: 'Vuelta al estadio'),
        publicada(id: 'r-2', nombre: 'Subida a Nutibara'),
      ],
      tamano: const Size(320, 568),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Vuelta al estadio'), findsOneWidget);
    // La segunda entra en pantalla aunque sea en parte: es lo que invita a
    // arrastrar el carrusel.
    expect(find.text('Subida a Nutibara'), findsOneWidget);
  });
}
