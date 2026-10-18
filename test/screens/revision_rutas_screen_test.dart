import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/revision_ruta.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/revision_rutas_screen.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/revision_rutas_service.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/dialogo_motivo_rechazo.dart';
import 'package:traza/widgets/mapa_trayecto.dart';
import 'package:traza/widgets/tarjeta_revision_ruta.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/revision_rutas_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Las bandejas de revisión de rutas (SCRUM-327 y SCRUM-329).
///
/// Que solo entren el administrador y el Runner Experto lo cubren
/// `SoloAdministrador` y `SoloExperto`, con sus propias pruebas, y las rutas
/// del router (`revision_rutas_acceso_test`).
void main() {
  const trazado = [
    PuntoRuta(latitud: 6.2442, longitud: -75.5812),
    PuntoRuta(latitud: 6.2450, longitud: -75.5800),
  ];

  final recienEnviada = rutaDePrueba(
    id: 'nueva',
    nombre: 'Loma de los Balsos',
    descripcion: 'Subida fuerte con buena sombra',
    trazado: trazado,
  );
  final aprobadaPorAdmin = rutaDePrueba(
    id: 'aprobada',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.revisionExperto,
    trazado: trazado,
  );

  late RevisionRutasFalso revision;

  Future<void> abrir(
    WidgetTester tester, {
    EtapaRevision etapa = EtapaRevision.administrador,
    List<Ruta>? rutas,
    Object? error,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final todas = rutas ?? [recienEnviada, aprobadaPorAdmin];
    revision = RevisionRutasFalso(rutas: todas, error: error);

    final router = GoRouter(
      initialLocation: etapa.ruta,
      routes: [
        GoRoute(
          path: etapa.ruta,
          builder: (_, _) => RevisionRutasScreen(etapa: etapa),
          routes: [
            GoRoute(
              path: ':rutaId',
              builder: (_, state) => RevisionRutaScreen(
                rutaId: state.pathParameters['rutaId']!,
                etapa: etapa,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          revisionRutasRepositoryProvider.overrideWithValue(revision),
          rutasRepositoryProvider.overrideWithValue(
            RutasRepositorioFalso(rutas: todas),
          ),
          usuarioActualProvider.overrideWithValue(() => 'revisor-1'),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rechazarCon(WidgetTester tester, String motivo) async {
    await tester.enterText(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
      motivo,
    );
    await tester.tap(find.byKey(DialogoMotivoRechazo.claveConfirmar));
    await tester.pumpAndSettle();
  }

  group('bandeja del administrador (SCRUM-327)', () {
    testWidgets('muestra lo recien enviado con nombre, descripcion y autor', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.text('Revisión de rutas'), findsOneWidget);
      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsOneWidget);
      expect(find.text('Loma de los Balsos'), findsOneWidget);
      expect(find.text('Subida fuerte con buena sombra'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(
        find.textContaining('Pendiente de revisión del administrador'),
        findsOneWidget,
      );
    });

    testWidgets('no muestra lo que ya espera al Runner Experto', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.byKey(TarjetaRevisionRuta.claveDe('aprobada')), findsNothing);
    });

    testWidgets('aprobar la manda al Runner Experto y sale de la bandeja', (
      tester,
    ) async {
      await abrir(tester);

      await tester.tap(find.byKey(TarjetaRevisionRuta.claveAprobar('nueva')));
      await tester.pumpAndSettle();

      expect(revision.decisiones.single, ('nueva', true, null));
      expect(find.text('Aprobada. Pasa a un Runner Experto.'), findsOneWidget);
      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsNothing);
      expect(find.text('No hay rutas por revisar'), findsOneWidget);
    });

    testWidgets('rechazar sin motivo no se completa (criterio 6)', (
      tester,
    ) async {
      await abrir(tester);

      await tester.tap(find.byKey(TarjetaRevisionRuta.claveRechazar('nueva')));
      await tester.pumpAndSettle();
      await rechazarCon(tester, '   ');

      expect(find.text('El motivo es obligatorio.'), findsOneWidget);
      expect(revision.decisiones, isEmpty);
    });

    testWidgets('rechazar con motivo la deja rechazada (criterio 3)', (
      tester,
    ) async {
      await abrir(tester);

      await tester.tap(find.byKey(TarjetaRevisionRuta.claveRechazar('nueva')));
      await tester.pumpAndSettle();
      await rechazarCon(tester, 'Cruza una autopista');

      expect(revision.decisiones.single, (
        'nueva',
        false,
        'Cruza una autopista',
      ));
      expect(
        find.text('Rechazada. Le avisamos al autor el motivo.'),
        findsOneWidget,
      );
      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsNothing);
      // No pasa a la etapa del experto.
      expect(
        revision.rutas.firstWhere((r) => r.id == 'nueva').estado,
        EstadoRuta.rechazada,
      );
    });

    testWidgets('cancelar el rechazo no decide nada', (tester) async {
      await abrir(tester);

      await tester.tap(find.byKey(TarjetaRevisionRuta.claveRechazar('nueva')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(revision.decisiones, isEmpty);
      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsOneWidget);
    });

    testWidgets('si otro revisor decidio primero lo avisa', (tester) async {
      await abrir(tester);
      revision.errorAlDecidir = const RutaYaRevisadaException();

      await tester.tap(find.byKey(TarjetaRevisionRuta.claveAprobar('nueva')));
      await tester.pumpAndSettle();

      expect(find.text('Esta ruta ya fue revisada.'), findsOneWidget);
    });

    testWidgets('sin rutas lo dice', (tester) async {
      await abrir(tester, rutas: [aprobadaPorAdmin]);

      expect(find.text('No hay rutas por revisar'), findsOneWidget);
      expect(
        find.text('Cuando alguien publique una ruta, aparecerá aquí.'),
        findsOneWidget,
      );
    });

    testWidgets('si no carga deja reintentar', (tester) async {
      await abrir(tester, error: Exception('sin red'));

      expect(find.text('No pudimos cargar las rutas'), findsOneWidget);

      revision.error = null;
      await tester.tap(find.byKey(RevisionRutasScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsOneWidget);
    });
  });

  group('detalle de la revision', () {
    testWidgets('muestra el trazado y deja decidir', (tester) async {
      await abrir(tester);

      await tester.tap(find.byKey(TarjetaRevisionRuta.claveDe('nueva')));
      await tester.pumpAndSettle();

      expect(find.byType(RevisionRutaScreen), findsOneWidget);
      expect(find.byType(MapaTrayecto), findsOneWidget);
      expect(find.text('Por Ana'), findsOneWidget);
      expect(find.text('Subida fuerte con buena sombra'), findsOneWidget);

      await tester.tap(find.byKey(RevisionRutaScreen.claveAprobar));
      await tester.pumpAndSettle();

      expect(revision.decisiones.single, ('nueva', true, null));
      // Vuelve a la bandeja, ya sin la ruta.
      expect(find.byType(RevisionRutaScreen), findsNothing);
      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsNothing);
    });

    testWidgets('rechazar desde el detalle tambien pide el motivo', (
      tester,
    ) async {
      await abrir(tester);
      await tester.tap(find.byKey(TarjetaRevisionRuta.claveDe('nueva')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(RevisionRutaScreen.claveRechazar));
      await tester.pumpAndSettle();
      await rechazarCon(tester, '');

      expect(find.text('El motivo es obligatorio.'), findsOneWidget);
      expect(revision.decisiones, isEmpty);
    });

    testWidgets('una ruta que no espera a esta etapa no ofrece decidir', (
      tester,
    ) async {
      // El administrador abre una que ya aprobó: ahora es del experto.
      await abrir(tester);
      final router = GoRouter.of(
        tester.element(find.byType(RevisionRutasScreen)),
      );
      router.push(EtapaRevision.administrador.detalleDe('aprobada'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Pendiente de revisión del Runner Experto'),
        findsOneWidget,
      );
      expect(find.byKey(RevisionRutaScreen.claveAprobar), findsNothing);
      expect(find.byKey(RevisionRutaScreen.claveRechazar), findsNothing);
    });
  });

  group('bandeja del Runner Experto (SCRUM-329)', () {
    testWidgets('solo ve lo que el administrador ya aprobo', (tester) async {
      await abrir(tester, etapa: EtapaRevision.experto);

      expect(find.text('Rutas por revisar'), findsOneWidget);
      expect(
        find.byKey(TarjetaRevisionRuta.claveDe('aprobada')),
        findsOneWidget,
      );
      expect(find.byKey(TarjetaRevisionRuta.claveDe('nueva')), findsNothing);
    });

    testWidgets('aprobar la publica (criterio 4)', (tester) async {
      await abrir(tester, etapa: EtapaRevision.experto);

      await tester.tap(
        find.byKey(TarjetaRevisionRuta.claveAprobar('aprobada')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Aprobada. Ya la ve toda la comunidad.'),
        findsOneWidget,
      );
      expect(
        revision.rutas.firstWhere((r) => r.id == 'aprobada').publicada,
        isTrue,
      );
    });

    testWidgets('rechazar con motivo no la publica (criterio 5)', (
      tester,
    ) async {
      await abrir(tester, etapa: EtapaRevision.experto);

      await tester.tap(
        find.byKey(TarjetaRevisionRuta.claveRechazar('aprobada')),
      );
      await tester.pumpAndSettle();
      await rechazarCon(tester, 'No es apta para principiantes');

      final ruta = revision.rutas.firstWhere((r) => r.id == 'aprobada');
      expect(ruta.estado, EstadoRuta.rechazada);
      expect(ruta.motivoRechazo, 'No es apta para principiantes');
    });

    testWidgets('sin rutas explica de donde le llegan', (tester) async {
      await abrir(tester, etapa: EtapaRevision.experto, rutas: [recienEnviada]);

      expect(
        find.text('Cuando el administrador apruebe una ruta, aparecerá aquí.'),
        findsOneWidget,
      );
    });
  });
}
