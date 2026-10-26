import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas de la dificultad en el detalle de una ruta, y de si la revisó un
/// Runner Experto (SCRUM-264, criterio 5 de HU-35).
void main() {
  final ahora = DateTime(2026, 10, 24, 12);
  final ayer = DateTime(2026, 10, 23, 18);

  Ruta ruta({
    Dificultad? dificultad = Dificultad.moderada,
    DateTime? revisadaEn,
  }) => rutaDePrueba(
    id: 'ruta-1',
    nombre: 'Subida al Volador',
    estado: EstadoRuta.publicada,
    dificultad: dificultad,
    dificultadRevisadaEn: revisadaEn,
    trazado: const [
      PuntoRuta(latitud: 6.2650, longitud: -75.5800),
      PuntoRuta(latitud: 6.2680, longitud: -75.5760),
    ],
    fechaPublicacion: DateTime(2026, 10, 20, 9),
  );

  Future<void> abrir(
    WidgetTester tester,
    Ruta ruta, {
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: DetalleRutaScreen.rutaDe('ruta-1'),
      routes: [
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
          rutasRepositoryProvider.overrideWithValue(
            RutasRepositorioFalso(rutas: [ruta]),
          ),
          relojProvider.overrideWithValue(() => ahora),
          // El mapa no descarga tiles reales.
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder enLaTarjeta(Finder finder) => find.descendant(
    of: find.byKey(DetalleRutaScreen.claveDificultad),
    matching: finder,
  );

  testWidgets('una ruta revisada dice su dificultad, que la revisó un Runner '
      'Experto y cuándo', (tester) async {
    await abrir(tester, ruta(revisadaEn: ayer));

    expect(enLaTarjeta(find.text('Moderada')), findsOneWidget);
    expect(
      enLaTarjeta(find.text('Revisada por un Runner Experto · Ayer')),
      findsOneWidget,
    );
    expect(enLaTarjeta(find.byIcon(Icons.verified_rounded)), findsOneWidget);
  });

  testWidgets('con dificultad pero sin revisar, lo dice', (tester) async {
    await abrir(tester, ruta());

    expect(enLaTarjeta(find.text('Moderada')), findsOneWidget);
    expect(
      enLaTarjeta(find.text(DetalleRutaScreen.sinRevisar)),
      findsOneWidget,
    );
    expect(enLaTarjeta(find.byIcon(Icons.verified_rounded)), findsNothing);
  });

  testWidgets('sin dificultad va "Sin clasificar", como en su tarjeta', (
    tester,
  ) async {
    await abrir(tester, ruta(dificultad: null));

    expect(
      enLaTarjeta(find.text(TarjetaRutaExplorar.sinDificultad)),
      findsOneWidget,
    );
    expect(
      enLaTarjeta(find.text(DetalleRutaScreen.sinDificultadAsignada)),
      findsOneWidget,
    );
  });

  testWidgets('sin dificultad, una fecha de revisión suelta no dice que la '
      'revisaron', (tester) async {
    await abrir(tester, ruta(dificultad: null, revisadaEn: ayer));

    expect(
      enLaTarjeta(find.textContaining('Revisada por un Runner Experto')),
      findsNothing,
    );
    expect(
      enLaTarjeta(find.text(DetalleRutaScreen.sinDificultadAsignada)),
      findsOneWidget,
    );
  });

  testWidgets('va justo debajo de la distancia', (tester) async {
    await abrir(tester, ruta(revisadaEn: ayer));

    expect(
      tester.getTopLeft(find.byKey(DetalleRutaScreen.claveDificultad)).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(DetalleRutaScreen.claveDistancia)).dy,
      ),
    );
  });

  testWidgets('un lector de pantalla lee la dificultad junto con quién la '
      'revisó', (tester) async {
    final semantica = tester.ensureSemantics();
    await abrir(tester, ruta(revisadaEn: ayer));

    final etiqueta = tester
        .getSemantics(find.byKey(DetalleRutaScreen.claveDificultad))
        .label;
    expect(etiqueta, contains('Moderada'));
    expect(etiqueta, contains('Revisada por un Runner Experto · Ayer'));
    semantica.dispose();
  });

  testWidgets('en la pantalla más estrecha con el texto grande no desborda', (
    tester,
  ) async {
    await abrir(
      tester,
      ruta(revisadaEn: ayer),
      tamano: const Size(320, 568),
      escalaTexto: 1.6,
    );

    expect(tester.takeException(), isNull);
  });
}
