import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/screens/admin/formulario_recompensa_screen.dart';
import 'package:traza/screens/admin/gestion_recompensas_screen.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/widgets/tarjeta_recompensa.dart';

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas de la gestión de recompensas del administrador (SCRUM-374): la
/// lista de todo lo creado y la entrada al formulario.
void main() {
  final hidratacion = recompensaDePrueba(
    id: 'recompensa-hidratacion',
    fechaCreacion: DateTime(2026, 10, 2),
  );
  final camiseta = recompensaDePrueba(
    id: 'recompensa-camiseta',
    nombre: 'Camiseta edición limitada',
    descripcion: 'Camiseta técnica con el logo de TRAZA.',
    puntos: 900,
    disponible: false,
    fechaCreacion: DateTime(2026, 10, 1),
  );

  late RecompensasRepositorioFalso repositorio;

  Future<void> abrirGestion(
    WidgetTester tester, {
    List<Recompensa>? recompensas,
    Object? error,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = RecompensasRepositorioFalso(
      recompensas: recompensas ?? [hidratacion, camiseta],
    )..error = error;
    final router = GoRouter(
      initialLocation: GestionRecompensasScreen.ruta,
      routes: [
        GoRoute(
          path: GestionRecompensasScreen.ruta,
          builder: (_, _) => const GestionRecompensasScreen(),
        ),
        GoRoute(
          path: GestionRecompensasScreen.rutaNueva,
          builder: (_, _) => const FormularioRecompensaScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recompensasRepositoryProvider.overrideWithValue(repositorio),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lo que dice la tarjeta de la recompensa con [id].
  Finder enLaTarjeta(String id, String texto) => find.descendant(
    of: find.byKey(TarjetaRecompensa.claveDe(id)),
    matching: find.text(texto),
  );

  group('lista', () {
    testWidgets('muestra cada recompensa con sus puntos y si está '
        'disponible', (tester) async {
      await abrirGestion(tester);

      expect(find.text('Gestión de recompensas'), findsOneWidget);
      expect(
        enLaTarjeta('recompensa-hidratacion', 'Vale de hidratación'),
        findsOneWidget,
      );
      expect(
        enLaTarjeta('recompensa-hidratacion', '150 puntos'),
        findsOneWidget,
      );
      expect(
        enLaTarjeta('recompensa-hidratacion', 'Disponible'),
        findsOneWidget,
      );
    });

    testWidgets('también muestra las que no están disponibles, marcadas '
        'como tales', (tester) async {
      await abrirGestion(tester);

      expect(
        enLaTarjeta('recompensa-camiseta', 'Camiseta edición limitada'),
        findsOneWidget,
      );
      expect(enLaTarjeta('recompensa-camiseta', '900 puntos'), findsOneWidget);
      expect(
        enLaTarjeta('recompensa-camiseta', 'No disponible'),
        findsOneWidget,
      );
    });

    testWidgets('sin recompensas lo dice', (tester) async {
      await abrirGestion(tester, recompensas: []);

      expect(find.text('Todavía no hay recompensas'), findsOneWidget);
      expect(find.byType(TarjetaRecompensa), findsNothing);
    });

    testWidgets('si la consulta falla lo dice y permite reintentar', (
      tester,
    ) async {
      await abrirGestion(tester, error: Exception('sin red'));

      expect(find.text('No pudimos cargar las recompensas'), findsOneWidget);

      // Vuelve la conexión.
      repositorio.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar las recompensas'), findsNothing);
      expect(find.byType(TarjetaRecompensa), findsNWidgets(2));
    });
  });

  group('crear una recompensa (criterio 1 de SCRUM-374)', () {
    testWidgets('el botón + abre el formulario', (tester) async {
      await abrirGestion(tester);

      await tester.tap(find.byKey(GestionRecompensasScreen.claveBotonNueva));
      await tester.pumpAndSettle();

      expect(find.byType(FormularioRecompensaScreen), findsOneWidget);
      expect(find.text('Nueva recompensa'), findsOneWidget);
    });

    testWidgets('al guardar vuelve a la gestión con la recompensa nueva y sus '
        'puntos en la lista', (tester) async {
      await abrirGestion(tester);

      await tester.tap(find.byKey(GestionRecompensasScreen.claveBotonNueva));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(FormularioRecompensaScreen.claveNombre),
        'Gorra TRAZA',
      );
      await tester.enterText(
        find.byKey(FormularioRecompensaScreen.claveDescripcion),
        'Gorra para correr bajo el sol.',
      );
      await tester.enterText(
        find.byKey(FormularioRecompensaScreen.clavePuntos),
        '500',
      );
      await tester.tap(find.byKey(FormularioRecompensaScreen.claveGuardar));
      await tester.pumpAndSettle();

      expect(find.byType(GestionRecompensasScreen), findsOneWidget);
      expect(find.byType(FormularioRecompensaScreen), findsNothing);
      expect(find.text('Recompensa creada'), findsOneWidget);
      final nueva = find.ancestor(
        of: find.text('Gorra TRAZA'),
        matching: find.byType(TarjetaRecompensa),
      );
      expect(nueva, findsOneWidget);
      expect(
        find.descendant(of: nueva, matching: find.text('500 puntos')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: nueva, matching: find.text('Disponible')),
        findsOneWidget,
      );
      // Las que ya había siguen ahí.
      expect(find.byType(TarjetaRecompensa), findsNWidgets(3));
    });

    testWidgets('al volver del formulario sin guardar, la lista se vuelve a '
        'consultar', (tester) async {
      await abrirGestion(tester);
      final antes = repositorio.consultasTodas;

      await tester.tap(find.byKey(GestionRecompensasScreen.claveBotonNueva));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      expect(repositorio.consultasTodas, greaterThan(antes));
    });
  });
}
