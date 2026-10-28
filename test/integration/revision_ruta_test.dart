// El recorrido completo de la validación de una ruta (SCRUM-321 + SCRUM-363,
// como lo dejó 0048): el administrador la aprueba o la rechaza en su
// bandeja, y el Runner Experto, desde el detalle, le asigna la dificultad o
// también la rechaza.
//
// Las decisiones van por dos repositorios en memoria: `RevisionRutasFalso`
// (`decidir_revision_ruta`) y `RutasRepositorioFalso` (`clasificar_ruta`).
// En la app son la misma tabla; aquí la prueba los sincroniza al pasar de
// una etapa a la otra. Las barreras de rol tienen su propia prueba
// (`revision_rutas_acceso_test`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/revision_rutas_screen.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/revision_rutas_service.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/dialogo_motivo_rechazo.dart';
import 'package:traza/widgets/tarjeta_revision_ruta.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/revision_rutas_falso.dart';
import '../utiles/roles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

void main() {
  late RevisionRutasFalso revision;
  late RutasRepositorioFalso rutas;
  late GoRouter router;

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final enviadas = [
      rutaDePrueba(id: 'buena', nombre: 'Loma de los Balsos'),
      rutaDePrueba(id: 'spam', nombre: 'Gana dinero corriendo'),
    ];
    revision = RevisionRutasFalso(rutas: enviadas);
    rutas = RutasRepositorioFalso(rutas: enviadas, usuario: 'revisor-1');

    router = GoRouter(
      initialLocation: RevisionRutasScreen.ruta,
      routes: [
        GoRoute(
          path: RevisionRutasScreen.ruta,
          builder: (_, _) => const RevisionRutasScreen(),
        ),
        GoRoute(
          path: DetalleRutaScreen.ruta,
          builder: (_, estado) =>
              DetalleRutaScreen(rutaId: estado.pathParameters['rutaId']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          revisionRutasRepositoryProvider.overrideWithValue(revision),
          rutasRepositoryProvider.overrideWithValue(rutas),
          // La misma persona hace de administrador y de experto: las
          // barreras de rol no son de esta prueba.
          rolesRepositoryProvider.overrideWithValue(RolesFalso.experto()),
          usuarioActualProvider.overrideWithValue(() => 'revisor-1'),
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 27, 12)),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lo que el administrador aprobó llega a la tabla que lee el experto.
  void pasarAlExperto(String id) => rutas.aprobarComoAdministrador(id);

  Future<void> abrirComoExperto(WidgetTester tester, String id) async {
    router.push(DetalleRutaScreen.rutaDe(id));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder objetivo) async {
    await tester.ensureVisible(objetivo);
    await tester.pumpAndSettle();
    await tester.tap(objetivo);
    await tester.pumpAndSettle();
  }

  Ruta ruta(String id) => revision.rutas.firstWhere((r) => r.id == id);

  testWidgets('una ruta pasa al experto y queda clasificada, y otra se '
      'queda en la primera revision', (tester) async {
    await montar(tester);

    // 1. El administrador ve las dos recién enviadas (criterio 1: ninguna
    //    está publicada todavía).
    expect(find.byKey(TarjetaRevisionRuta.claveDe('buena')), findsOneWidget);
    expect(find.byKey(TarjetaRevisionRuta.claveDe('spam')), findsOneWidget);
    expect(ruta('buena').publicada, isFalse);

    // 2. Rechaza una sin motivo: no se completa (criterio 6).
    await tester.tap(find.byKey(TarjetaRevisionRuta.claveRechazar('spam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DialogoMotivoRechazo.claveConfirmar));
    await tester.pumpAndSettle();
    expect(find.text('El motivo es obligatorio.'), findsOneWidget);
    expect(ruta('spam').estado, EstadoRuta.enRevision);

    // 3. Con motivo, queda rechazada y no pasa al experto (criterio 3).
    await tester.enterText(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
      'Es publicidad, no una ruta',
    );
    await tester.tap(find.byKey(DialogoMotivoRechazo.claveConfirmar));
    await tester.pumpAndSettle();
    expect(ruta('spam').estado, EstadoRuta.rechazada);
    expect(ruta('spam').motivoRechazo, 'Es publicidad, no una ruta');

    // 4. Aprueba la otra: pasa al Runner Experto, sin publicarse
    //    (criterio 2).
    await tester.tap(find.byKey(TarjetaRevisionRuta.claveAprobar('buena')));
    await tester.pumpAndSettle();
    expect(ruta('buena').estado, EstadoRuta.revisionExperto);
    expect(ruta('buena').publicada, isFalse);
    expect(find.text('No hay rutas por revisar'), findsOneWidget);

    // 5. El experto la abre y aprueba asignándole la dificultad
    //    (criterio 4, por `clasificar_ruta` desde 0048). Queda lista para
    //    que su autor la publique.
    pasarAlExperto('buena');
    await abrirComoExperto(tester, 'buena');
    await tocar(
      tester,
      find.byKey(DetalleRutaScreen.claveOpcionDificultad(Dificultad.moderada)),
    );
    await tocar(tester, find.byKey(DetalleRutaScreen.claveAsignar));

    final clasificada = rutas.rutas.firstWhere((r) => r.id == 'buena');
    expect(clasificada.estado, EstadoRuta.clasificada);
    expect(clasificada.publicada, isFalse);

    expect(revision.decisiones, [
      ('spam', false, 'Es publicidad, no una ruta'),
      ('buena', true, null),
    ]);
  });

  testWidgets('el Runner Experto tambien puede rechazar con motivo '
      '(criterio 5)', (tester) async {
    await montar(tester);

    await tester.tap(find.byKey(TarjetaRevisionRuta.claveAprobar('buena')));
    await tester.pumpAndSettle();
    pasarAlExperto('buena');
    // Que se vaya el aviso de la aprobación: tapa el pie de la pantalla,
    // donde queda "Rechazar".
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await abrirComoExperto(tester, 'buena');
    await tocar(tester, find.byKey(DetalleRutaScreen.claveRechazar));
    await tester.enterText(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
      'Pasa por una zona sin andén',
    );
    await tocar(tester, find.byKey(DialogoMotivoRechazo.claveConfirmar));

    expect(ruta('buena').estado, EstadoRuta.rechazada);
    expect(ruta('buena').publicada, isFalse);
    expect(ruta('buena').motivoRechazo, 'Pasa por una zona sin andén');
    // Vuelve a donde estaba.
    expect(find.byType(DetalleRutaScreen), findsNothing);
  });
}
