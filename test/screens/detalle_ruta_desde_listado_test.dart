import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/mapa_trayecto.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// La ruta completa no llega hasta que la prueba lo decida.
class _DetalleLento extends RutasRepositorioFalso {
  final espera = Completer<Ruta?>();

  @override
  Future<Ruta?> ruta(String id) => espera.future;
}

/// Pruebas del detalle de una ruta abierto desde un listado (SCRUM-250).
///
/// Los listados no traen el trazado, así que el detalle igual pide la ruta
/// completa. Mientras llega, muestra lo que ya sabe de ella por el listado
/// en vez de una pantalla en blanco.
void main() {
  const trazado = [
    PuntoRuta(latitud: 6.2442, longitud: -75.5812),
    PuntoRuta(latitud: 6.2445, longitud: -75.5808),
    PuntoRuta(latitud: 6.2448, longitud: -75.5809),
    PuntoRuta(latitud: 6.2444, longitud: -75.5802),
  ];

  // Como llega en el listado: sin el trazado, con una miniatura más gruesa.
  final delListado = rutaDePrueba(
    nombre: 'Vuelta al Parque Norte',
    descripcion: 'Plana y con sombra.',
    estado: EstadoRuta.publicada,
    fechaPublicacion: DateTime(2026, 10, 17, 9),
    miniatura: [trazado.first, trazado.last],
  );

  // Como llega al pedirla por su id: con el trazado completo.
  final completa = rutaDePrueba(
    nombre: 'Vuelta al Parque Norte',
    descripcion: 'Plana y con sombra.',
    estado: EstadoRuta.publicada,
    fechaPublicacion: DateTime(2026, 10, 17, 9),
    trazado: trazado,
  );

  Future<_DetalleLento> abrir(
    WidgetTester tester, {
    Ruta? vistaPrevia,
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repositorio = _DetalleLento();
    final router = GoRouter(
      initialLocation: DetalleRutaScreen.rutaDe('ruta-1'),
      routes: [
        GoRoute(
          path: DetalleRutaScreen.ruta,
          builder: (_, estado) => DetalleRutaScreen(
            rutaId: estado.pathParameters['rutaId']!,
            vistaPrevia: vistaPrevia,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 12)),
          // El mapa no descarga tiles reales.
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    // Con un indicador de carga girando no se asienta: basta un cuadro.
    await tester.pump();
    return repositorio;
  }

  testWidgets('mientras llega el trazado, muestra lo que ya se sabe de la '
      'ruta', (tester) async {
    await abrir(tester, vistaPrevia: delListado);

    expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
    expect(find.text('Por Ana · Hoy'), findsOneWidget);
    expect(find.text('5.23 km'), findsOneWidget);
    expect(find.text('Plana y con sombra.'), findsOneWidget);
    // El mapa dice que el recorrido viene en camino...
    expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsOneWidget);
    // ...y no que la ruta no lo guardó, que sería falso.
    expect(find.text('Esta ruta no guardó su trazado'), findsNothing);
    expect(find.byType(MapaTrayecto), findsNothing);
  });

  testWidgets('a un lector de pantalla le dice que el recorrido está '
      'cargando', (tester) async {
    final semantica = tester.ensureSemantics();
    await abrir(tester, vistaPrevia: delListado);

    expect(find.bySemanticsLabel('Cargando el recorrido'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('cuando llega, el mapa dibuja el recorrido completo, no la '
      'miniatura del listado', (tester) async {
    final repositorio = await abrir(tester, vistaPrevia: delListado);

    repositorio.espera.complete(completa);
    await tester.pumpAndSettle();

    expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsNothing);
    expect(find.byType(MapaTrayecto), findsOneWidget);
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single
          .points,
      [for (final punto in trazado) LatLng(punto.latitud, punto.longitud)],
    );
    // Lo demás sigue donde estaba.
    expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
    expect(find.text('5.23 km'), findsOneWidget);
  });

  testWidgets('si la ruta ya no está, lo dice aunque el listado la mostrara', (
    tester,
  ) async {
    final repositorio = await abrir(tester, vistaPrevia: delListado);

    // La retiraron entre que se vio en la lista y se abrió.
    repositorio.espera.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Esta ruta ya no está disponible'), findsOneWidget);
    expect(find.text('Vuelta al Parque Norte'), findsNothing);
    expect(find.byKey(DetalleRutaScreen.claveDistancia), findsNothing);
  });

  testWidgets('si falla la lectura, lo dice y deja reintentar, igual que '
      'sin ella', (tester) async {
    final repositorio = await abrir(tester, vistaPrevia: delListado);

    repositorio.espera.completeError(StateError('sin red'));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos mostrar el recorrido'), findsOneWidget);
    expect(find.byKey(DetalleRutaScreen.claveReintentar), findsOneWidget);
    expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsNothing);
  });

  testWidgets('sin la ruta del listado, mientras carga no muestra nada a '
      'medias', (tester) async {
    await abrir(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsNothing);
    expect(find.byKey(DetalleRutaScreen.claveDistancia), findsNothing);
  });

  testWidgets('en la pantalla más estrecha con texto grande no desborda '
      'mientras carga', (tester) async {
    await abrir(
      tester,
      vistaPrevia: delListado,
      tamano: const Size(320, 568),
      escalaTexto: 1.6,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsOneWidget);
  });
}
