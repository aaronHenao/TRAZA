import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/screens/admin/formulario_recompensa_screen.dart';
import 'package:traza/screens/admin/gestion_recompensas_screen.dart';
import 'package:traza/services/recompensas_provider.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;
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

  group('cambiar los puntos (SCRUM-380)', () {
    final dialogo = find.byType(AlertDialog);

    Future<void> abrirCambioDePuntos(WidgetTester tester, String id) async {
      await tester.tap(
        find.byKey(GestionRecompensasScreen.claveCambiarPuntos(id)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> guardarPuntos(WidgetTester tester, String texto) async {
      await tester.enterText(
        find.byKey(GestionRecompensasScreen.claveCampoPuntos),
        texto,
      );
      await tester.tap(find.byKey(GestionRecompensasScreen.claveGuardarPuntos));
      await tester.pumpAndSettle();
    }

    /// Lo escrito en el campo del diálogo, sea `TextField` o
    /// `TextFormField`.
    Finder enElCampo(String texto) => find.descendant(
      of: find.byKey(GestionRecompensasScreen.claveCampoPuntos),
      matching: find.text(texto),
    );

    testWidgets('cada tarjeta tiene su botón para cambiar los puntos', (
      tester,
    ) async {
      await abrirGestion(tester);

      for (final id in ['recompensa-hidratacion', 'recompensa-camiseta']) {
        final boton = find.descendant(
          of: find.byKey(TarjetaRecompensa.claveDe(id)),
          matching: find.byKey(GestionRecompensasScreen.claveCambiarPuntos(id)),
        );
        expect(boton, findsOneWidget, reason: 'en la tarjeta $id');
        expect(
          find.descendant(of: boton, matching: find.text('Cambiar puntos')),
          findsOneWidget,
        );
      }
    });

    testWidgets('el botón abre un diálogo con los puntos actuales ya '
        'escritos', (tester) async {
      await abrirGestion(tester);

      await abrirCambioDePuntos(tester, 'recompensa-hidratacion');

      expect(dialogo, findsOneWidget);
      expect(
        find.descendant(of: dialogo, matching: find.text('Cambiar puntos')),
        findsOneWidget,
      );
      expect(enElCampo('150'), findsOneWidget);
      expect(
        find.descendant(of: dialogo, matching: find.text('Cancelar')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialogo,
          matching: find.byKey(GestionRecompensasScreen.claveGuardarPuntos),
        ),
        findsOneWidget,
      );
      // Abrir no guarda nada.
      expect(repositorio.puntosRecibidos, isNull);
    });

    testWidgets('el diálogo de cada tarjeta arranca con sus propios puntos', (
      tester,
    ) async {
      await abrirGestion(tester);

      await abrirCambioDePuntos(tester, 'recompensa-camiseta');

      expect(enElCampo('900'), findsOneWidget);
    });

    testWidgets('al guardar un valor válido la tarjeta muestra los puntos '
        'nuevos y lo avisa (criterio 1 de SCRUM-380)', (tester) async {
      await abrirGestion(tester);
      await abrirCambioDePuntos(tester, 'recompensa-hidratacion');

      await guardarPuntos(tester, '200');

      expect(dialogo, findsNothing);
      expect(find.text('Puntos actualizados'), findsOneWidget);
      expect(
        enLaTarjeta('recompensa-hidratacion', '200 puntos'),
        findsOneWidget,
      );
      expect(enLaTarjeta('recompensa-hidratacion', '150 puntos'), findsNothing);
      expect(repositorio.recompensaPorCambiar?.id, 'recompensa-hidratacion');
      expect(repositorio.puntosRecibidos, 200);
      // La otra no se tocó.
      expect(enLaTarjeta('recompensa-camiseta', '900 puntos'), findsOneWidget);
    });

    for (final (texto, mensaje) in [
      ('0', 'Los puntos deben ser mayores que cero.'),
      ('-5', 'Los puntos deben ser mayores que cero.'),
      ('abc', 'Usa solo números enteros.'),
      ('0x10', 'Usa solo números enteros.'),
      ('', 'Indica cuántos puntos cuesta.'),
    ]) {
      testWidgets('con "$texto" no guarda: el diálogo sigue abierto, dice que '
          'la cantidad no es válida y la tarjeta conserva el valor anterior '
          '(criterio 2 de SCRUM-380)', (tester) async {
        await abrirGestion(tester);
        await abrirCambioDePuntos(tester, 'recompensa-hidratacion');

        await guardarPuntos(tester, texto);

        expect(dialogo, findsOneWidget);
        expect(
          find.descendant(of: dialogo, matching: find.text(mensaje)),
          findsOneWidget,
        );
        expect(repositorio.puntosRecibidos, isNull);
        expect(find.text('Puntos actualizados'), findsNothing);
        expect(
          enLaTarjeta('recompensa-hidratacion', '150 puntos'),
          findsOneWidget,
        );
      });
    }

    testWidgets('tras corregir una cantidad inválida, sí guarda (criterios 1 '
        'y 2 de SCRUM-380)', (tester) async {
      await abrirGestion(tester);
      await abrirCambioDePuntos(tester, 'recompensa-hidratacion');
      await guardarPuntos(tester, '0');
      expect(dialogo, findsOneWidget);

      await guardarPuntos(tester, '250');

      expect(dialogo, findsNothing);
      expect(repositorio.puntosRecibidos, 250);
      expect(
        enLaTarjeta('recompensa-hidratacion', '250 puntos'),
        findsOneWidget,
      );
    });

    testWidgets('cancelar cierra el diálogo sin guardar nada', (tester) async {
      await abrirGestion(tester);
      await abrirCambioDePuntos(tester, 'recompensa-hidratacion');
      await tester.enterText(
        find.byKey(GestionRecompensasScreen.claveCampoPuntos),
        '300',
      );

      await tester.tap(
        find.descendant(of: dialogo, matching: find.text('Cancelar')),
      );
      await tester.pumpAndSettle();

      expect(dialogo, findsNothing);
      expect(repositorio.puntosRecibidos, isNull);
      expect(find.text('Puntos actualizados'), findsNothing);
      expect(
        enLaTarjeta('recompensa-hidratacion', '150 puntos'),
        findsOneWidget,
      );
    });

    for (final (error, mensaje) in [
      (Exception('sin red'), CambioPuntosRecompensa.noSePudo),
      (
        const SoloAdministradorException(),
        CambioPuntosRecompensa.soloAdministrador,
      ),
      (
        const DatosDeRecompensaInvalidosException('recompensas_puntos_validos'),
        CambioPuntosRecompensa.datosRechazados,
      ),
    ]) {
      testWidgets('si el guardado falla ($error) lo dice y la tarjeta '
          'conserva el valor anterior', (tester) async {
        await abrirGestion(tester);
        await abrirCambioDePuntos(tester, 'recompensa-hidratacion');
        repositorio.error = error;

        await guardarPuntos(tester, '200');

        expect(find.text(mensaje), findsOneWidget);
        expect(find.text('Puntos actualizados'), findsNothing);
        expect(
          enLaTarjeta('recompensa-hidratacion', '150 puntos'),
          findsOneWidget,
        );
        expect(
          enLaTarjeta('recompensa-hidratacion', '200 puntos'),
          findsNothing,
        );
      });
    }
  });
}
