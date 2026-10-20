import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/screens/recompensas/catalogo_recompensas_screen.dart';
import 'package:traza/services/recompensas_provider.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/widgets/tarjeta_recompensa.dart';

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas del catálogo de recompensas que consulta el corredor
/// (SCRUM-374): lo disponible, con los puntos que cuesta.
void main() {
  final botella = recompensaDePrueba(
    id: 'recompensa-botella',
    nombre: 'Botella TRAZA',
    descripcion: 'Botella reutilizable de 750 ml.',
    puntos: 300,
  );
  final hidratacion = recompensaDePrueba(id: 'recompensa-hidratacion');
  final camiseta = recompensaDePrueba(
    id: 'recompensa-camiseta',
    nombre: 'Camiseta edición limitada',
    descripcion: 'Camiseta técnica con el logo de TRAZA.',
    puntos: 900,
    disponible: false,
  );

  late RecompensasRepositorioFalso repositorio;

  /// Monta la app en una portada de mentira desde la que se abre el
  /// catálogo, para tener a dónde volver.
  Future<void> montar(
    WidgetTester tester, {
    List<Recompensa>? recompensas,
    Object? error,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = RecompensasRepositorioFalso(
      recompensas: recompensas ?? [botella, hidratacion, camiseta],
    )..error = error;
    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(
          path: '/inicio',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(CatalogoRecompensasScreen.ruta),
              child: const Text('Inicio'),
            ),
          ),
        ),
        GoRoute(
          path: CatalogoRecompensasScreen.ruta,
          builder: (_, _) => const CatalogoRecompensasScreen(),
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

  Future<void> abrirCatalogo(WidgetTester tester) async {
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
  }

  Future<void> volver(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
  }

  /// Lo que dice la tarjeta de la recompensa con [id].
  Finder enLaTarjeta(String id, String texto) => find.descendant(
    of: find.byKey(TarjetaRecompensa.claveDe(id)),
    matching: find.text(texto),
  );

  List<String> nombresEnPantalla(WidgetTester tester) => tester
      .widgetList<TarjetaRecompensa>(find.byType(TarjetaRecompensa))
      .map((tarjeta) => tarjeta.recompensa.nombre)
      .toList();

  group('lo disponible, con sus puntos (criterio 3 de SCRUM-374)', () {
    testWidgets('muestra cada recompensa disponible junto con los puntos que '
        'cuesta', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);

      expect(find.text('Recompensas'), findsOneWidget);
      expect(
        enLaTarjeta('recompensa-hidratacion', 'Vale de hidratación'),
        findsOneWidget,
      );
      expect(
        enLaTarjeta(
          'recompensa-hidratacion',
          'Una bebida isotónica en la tienda aliada.',
        ),
        findsOneWidget,
      );
      expect(
        enLaTarjeta('recompensa-hidratacion', '150 puntos'),
        findsOneWidget,
      );
      expect(enLaTarjeta('recompensa-botella', '300 puntos'), findsOneWidget);
    });

    testWidgets('una recompensa no disponible no aparece', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);

      expect(find.text('Camiseta edición limitada'), findsNothing);
      expect(find.text('900 puntos'), findsNothing);
      expect(find.byType(TarjetaRecompensa), findsNWidgets(2));
    });

    testWidgets('van de la que menos puntos cuesta a la que más', (
      tester,
    ) async {
      await montar(tester);
      await abrirCatalogo(tester);

      expect(nombresEnPantalla(tester), [
        'Vale de hidratación',
        'Botella TRAZA',
      ]);
    });

    testWidgets('no habla de disponibilidad: todo lo que se ve se puede '
        'obtener', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);

      expect(find.text('Disponible'), findsNothing);
      expect(find.text('No disponible'), findsNothing);
    });
  });

  group('lo recién creado (criterios 1 y 3 de SCRUM-374)', () {
    testWidgets('una recompensa que el administrador acaba de crear aparece '
        'al abrir el catálogo, con sus puntos', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);
      expect(find.text('Gorra TRAZA'), findsNothing);
      await volver(tester);

      // El administrador crea dos: una disponible y otra todavía no.
      final crear = ProviderScope.containerOf(
        tester.element(find.text('Inicio')),
      ).read(creacionRecompensaProvider).crear;
      final gorra = await crear(
        const BorradorRecompensa(
          nombre: 'Gorra TRAZA',
          descripcion: 'Gorra para correr bajo el sol.',
          puntos: '500',
        ),
      );
      final medalla = await crear(
        const BorradorRecompensa(
          nombre: 'Medalla de finisher',
          descripcion: 'Se ofrecerá después de la carrera.',
          puntos: '200',
          disponible: false,
        ),
      );
      expect(gorra, isA<RecompensaCreada>());
      expect(medalla, isA<RecompensaCreada>());

      await abrirCatalogo(tester);

      final idGorra = (gorra as RecompensaCreada).recompensa.id;
      expect(enLaTarjeta(idGorra, 'Gorra TRAZA'), findsOneWidget);
      expect(enLaTarjeta(idGorra, '500 puntos'), findsOneWidget);
      // En su lugar según los puntos.
      expect(nombresEnPantalla(tester), [
        'Vale de hidratación',
        'Botella TRAZA',
        'Gorra TRAZA',
      ]);
      // La que no se marcó como disponible no le llega al corredor.
      expect(find.text('Medalla de finisher'), findsNothing);
    });
  });

  group('puntos que cambió el administrador (SCRUM-380)', () {
    /// Cambia los puntos como lo hace la gestión del administrador, sobre el
    /// mismo repositorio que consulta el catálogo.
    Future<ResultadoCambioPuntos> cambiarPuntos(
      WidgetTester tester,
      Recompensa recompensa,
      String texto,
    ) => ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    ).read(cambioPuntosRecompensaProvider).cambiar(recompensa, texto);

    testWidgets('tras cambiar los puntos, el corredor ve el valor nuevo al '
        'abrir el catálogo (criterio 1 de SCRUM-380)', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);
      expect(enLaTarjeta('recompensa-botella', '300 puntos'), findsOneWidget);
      await volver(tester);

      final resultado = await cambiarPuntos(tester, botella, '100');
      expect(resultado, isA<PuntosCambiados>());

      await abrirCatalogo(tester);

      expect(enLaTarjeta('recompensa-botella', '100 puntos'), findsOneWidget);
      expect(find.text('300 puntos'), findsNothing);
      // Y pasa a su nuevo lugar según los puntos.
      expect(nombresEnPantalla(tester), [
        'Botella TRAZA',
        'Vale de hidratación',
      ]);
    });

    testWidgets('con el catálogo abierto, el valor nuevo aparece sin tener '
        'que salir (criterio 1 de SCRUM-380)', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);

      await cambiarPuntos(tester, hidratacion, '450');
      await tester.pumpAndSettle();

      expect(
        enLaTarjeta('recompensa-hidratacion', '450 puntos'),
        findsOneWidget,
      );
      expect(find.text('150 puntos'), findsNothing);
    });

    testWidgets('una cantidad inválida no cambia lo que ve el corredor '
        '(criterio 2 de SCRUM-380)', (tester) async {
      await montar(tester);

      final resultado = await cambiarPuntos(tester, botella, '0');
      expect(resultado, isA<PuntosInvalidos>());

      await abrirCatalogo(tester);

      expect(enLaTarjeta('recompensa-botella', '300 puntos'), findsOneWidget);
    });

    testWidgets('el corredor no tiene cómo cambiar los puntos', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);

      expect(find.text('Cambiar puntos'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TarjetaRecompensa),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
        findsNothing,
      );
    });
  });

  group('estados de la lista', () {
    testWidgets('sin recompensas disponibles lo dice', (tester) async {
      await montar(tester, recompensas: [camiseta]);
      await abrirCatalogo(tester);

      expect(find.text('Todavía no hay recompensas'), findsOneWidget);
      expect(find.byType(TarjetaRecompensa), findsNothing);
    });

    testWidgets('si la consulta falla lo dice y permite reintentar', (
      tester,
    ) async {
      await montar(tester, error: Exception('sin red'));
      await abrirCatalogo(tester);

      expect(find.text('No pudimos cargar las recompensas'), findsOneWidget);

      // Vuelve la conexión.
      repositorio.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar las recompensas'), findsNothing);
      expect(find.byType(TarjetaRecompensa), findsNWidgets(2));
    });

    testWidgets('el botón de volver regresa a donde estaba', (tester) async {
      await montar(tester);
      await abrirCatalogo(tester);

      await volver(tester);

      expect(find.text('Inicio'), findsOneWidget);
      expect(find.byType(CatalogoRecompensasScreen), findsNothing);
    });
  });
}
