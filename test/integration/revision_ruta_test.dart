// El recorrido completo de la validación de una ruta (SCRUM-321): del
// administrador al Runner Experto, y de ahí a la comunidad o al rechazo.
//
// Monta las bandejas de verdad sobre un mismo repositorio en memoria, que
// mueve las rutas de etapa como lo hace `decidir_revision_ruta` (0036). Las
// barreras de rol tienen su propia prueba (`revision_rutas_acceso_test`).

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
import 'package:traza/widgets/tarjeta_revision_ruta.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/revision_rutas_falso.dart';
import '../utiles/rutas_repository_falso.dart';

void main() {
  late RevisionRutasFalso revision;
  late GoRouter router;

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    revision = RevisionRutasFalso(
      rutas: [
        rutaDePrueba(id: 'buena', nombre: 'Loma de los Balsos'),
        rutaDePrueba(id: 'spam', nombre: 'Gana dinero corriendo'),
      ],
    );

    router = GoRouter(
      initialLocation: EtapaRevision.administrador.ruta,
      routes: [
        for (final etapa in EtapaRevision.values)
          GoRoute(
            path: etapa.ruta,
            builder: (_, _) => RevisionRutasScreen(etapa: etapa),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          revisionRutasRepositoryProvider.overrideWithValue(revision),
          rutasRepositoryProvider.overrideWithValue(RutasRepositorioFalso()),
          usuarioActualProvider.overrideWithValue(() => 'revisor-1'),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Ruta ruta(String id) => revision.rutas.firstWhere((r) => r.id == id);

  testWidgets('una ruta pasa las dos revisiones y otra se queda en la '
      'primera', (tester) async {
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

    // 5. El experto solo ve la aprobada.
    router.go(EtapaRevision.experto.ruta);
    await tester.pumpAndSettle();
    expect(find.byKey(TarjetaRevisionRuta.claveDe('buena')), findsOneWidget);
    expect(find.byKey(TarjetaRevisionRuta.claveDe('spam')), findsNothing);

    // 6. La aprueba y queda publicada para la comunidad (criterio 4).
    await tester.tap(find.byKey(TarjetaRevisionRuta.claveAprobar('buena')));
    await tester.pumpAndSettle();
    expect(ruta('buena').publicada, isTrue);
    expect(find.text('Aprobada. Ya la ve toda la comunidad.'), findsOneWidget);

    expect(revision.decisiones, [
      ('spam', false, 'Es publicidad, no una ruta'),
      ('buena', true, null),
      ('buena', true, null),
    ]);
  });

  testWidgets('el Runner Experto tambien puede rechazar con motivo '
      '(criterio 5)', (tester) async {
    await montar(tester);

    await tester.tap(find.byKey(TarjetaRevisionRuta.claveAprobar('buena')));
    await tester.pumpAndSettle();

    router.go(EtapaRevision.experto.ruta);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TarjetaRevisionRuta.claveRechazar('buena')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
      'Pasa por una zona sin andén',
    );
    await tester.tap(find.byKey(DialogoMotivoRechazo.claveConfirmar));
    await tester.pumpAndSettle();

    expect(ruta('buena').estado, EstadoRuta.rechazada);
    expect(ruta('buena').publicada, isFalse);
    expect(ruta('buena').motivoRechazo, 'Pasa por una zona sin andén');
  });
}
