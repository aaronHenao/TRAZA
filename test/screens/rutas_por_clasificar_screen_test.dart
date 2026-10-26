import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/rutas_por_clasificar_screen.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/roles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// La bandeja del Runner Experto (SCRUM-363): las rutas que el
/// administrador ya aprobó y esperan su dificultad (SCRUM-321), de dónde se
/// abre cada una y qué pasa al volver.
void main() {
  final antigua = rutaDePrueba(
    id: 'ruta-antigua',
    autorId: 'autor-1',
    nombre: 'Vuelta al Parque Norte',
    autorNombre: 'Ana',
    estado: EstadoRuta.revisionExperto,
    fechaCreacion: DateTime(2026, 10, 16, 8),
  );
  final reciente = rutaDePrueba(
    id: 'ruta-reciente',
    autorId: 'autor-2',
    nombre: 'Subida a Las Palmas',
    autorNombre: 'Luis',
    estado: EstadoRuta.revisionExperto,
    fechaCreacion: DateTime(2026, 10, 17, 8),
  );

  testWidgets('lista las rutas que esperan al Runner Experto, la que más '
      'lleva esperando primero (criterio 1 de SCRUM-363)', (tester) async {
    await _abrir(
      tester,
      rutas: [
        reciente,
        antigua,
        // Ni lo que todavía espera al administrador (SCRUM-321), ni lo
        // publicado, ni lo que tiene la dificultad pendiente (criterio 3)
        // le llega.
        rutaDePrueba(
          id: 'ruta-del-admin',
          autorId: 'autor-3',
          nombre: 'Loma del Indio',
        ),
        rutaDePrueba(
          id: 'ruta-publicada',
          autorId: 'autor-3',
          nombre: 'Cerro Pan de Azúcar',
          estado: EstadoRuta.publicada,
          dificultad: Dificultad.dificil,
        ),
        rutaDePrueba(
          id: 'ruta-incompleta',
          autorId: 'autor-3',
          nombre: 'Paseo sin medir',
          estado: EstadoRuta.datosIncompletos,
          distanciaKm: null,
        ),
      ],
    );

    expect(find.text('Rutas por clasificar'), findsOneWidget);
    expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
    expect(find.text('Subida a Las Palmas'), findsOneWidget);
    expect(find.textContaining('Ana'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Vuelta al Parque Norte')).dy,
      lessThan(tester.getTopLeft(find.text('Subida a Las Palmas')).dy),
    );
    expect(find.text('Loma del Indio'), findsNothing);
    expect(find.text('Cerro Pan de Azúcar'), findsNothing);
    expect(find.text('Paseo sin medir'), findsNothing);
  });

  testWidgets('tocar una ruta abre su detalle para asignarle la dificultad', (
    tester,
  ) async {
    await _abrir(tester, rutas: [antigua]);

    await tester.tap(find.text('Vuelta al Parque Norte'));
    await tester.pumpAndSettle();

    expect(find.byType(DetalleRutaScreen), findsOneWidget);
    expect(find.byKey(DetalleRutaScreen.claveClasificar), findsOneWidget);
  });

  testWidgets('al asignarla vuelve a la bandeja y esa ruta ya no está', (
    tester,
  ) async {
    final repositorio = await _abrir(tester, rutas: [antigua, reciente]);

    await tester.tap(find.text('Vuelta al Parque Norte'));
    await tester.pumpAndSettle();
    await _tocar(
      tester,
      find.byKey(DetalleRutaScreen.claveOpcionDificultad(Dificultad.moderada)),
    );
    await _tocar(tester, find.byKey(DetalleRutaScreen.claveAsignar));

    expect(find.byType(RutasPorClasificarScreen), findsOneWidget);
    expect(find.text(ClasificacionRuta.clasificada), findsOneWidget);
    expect(find.text('Vuelta al Parque Norte'), findsNothing);
    expect(find.text('Subida a Las Palmas'), findsOneWidget);
    expect(
      repositorio.rutas.firstWhere((r) => r.id == 'ruta-antigua').estado,
      EstadoRuta.clasificada,
    );
  });

  testWidgets('al volver del detalle vuelve a preguntar: otro experto pudo '
      'adelantarse', (tester) async {
    final repositorio = await _abrir(tester, rutas: [antigua]);
    expect(repositorio.consultasPorClasificar, 1);

    await tester.tap(find.text('Vuelta al Parque Norte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(RutasPorClasificarScreen), findsOneWidget);
    expect(repositorio.consultasPorClasificar, 2);
  });

  testWidgets('sin rutas por clasificar lo dice en vez de quedar en blanco', (
    tester,
  ) async {
    await _abrir(tester, rutas: const []);

    expect(find.text('No hay rutas por clasificar'), findsOneWidget);
    // Le llegan después del administrador, no apenas se publican.
    expect(
      find.textContaining('Cuando el administrador apruebe una ruta'),
      findsOneWidget,
    );
  });

  testWidgets('si no carga lo dice, sin el error crudo, y deja reintentar', (
    tester,
  ) async {
    final repositorio = await _abrir(
      tester,
      rutas: [antigua],
      error: StateError('sin red'),
    );

    expect(find.text('No pudimos cargar las rutas'), findsOneWidget);
    expect(find.textContaining('sin red'), findsNothing);
    expect(find.text('Vuelta al Parque Norte'), findsNothing);

    repositorio.errorPorClasificar = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar las rutas'), findsNothing);
    expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
  });

  testWidgets('se abre desde otra pantalla y se puede volver a ella', (
    tester,
  ) async {
    await _abrir(tester, rutas: const []);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de perfil'), findsOneWidget);
  });
}

/// Lo trae a la vista antes de tocarlo.
Future<void> _tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.pumpAndSettle();
  await tester.tap(objetivo);
  await tester.pumpAndSettle();
}

/// Abre la bandeja como la abre el perfil (con `push`), con la sesión de un
/// Runner Experto que no es autor de ninguna de las rutas.
Future<RutasRepositorioFalso> _abrir(
  WidgetTester tester, {
  required List<Ruta> rutas,
  Object? error,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = RutasRepositorioFalso(rutas: rutas, usuario: 'experto-1')
    ..errorPorClasificar = error;

  final router = GoRouter(
    initialLocation: '/perfil',
    routes: [
      GoRoute(
        path: '/perfil',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de perfil')),
      ),
      GoRoute(
        path: RutasPorClasificarScreen.ruta,
        builder: (_, _) => const RutasPorClasificarScreen(),
      ),
      // Como en `seccionRutas`: si el listado manda la ruta en `extra`, el
      // detalle la usa mientras llega el trazado.
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
        usuarioActualProvider.overrideWithValue(() => 'experto-1'),
        rolesRepositoryProvider.overrideWithValue(RolesFalso.experto()),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 12)),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push(RutasPorClasificarScreen.ruta);
  await tester.pumpAndSettle();

  return repositorio;
}
