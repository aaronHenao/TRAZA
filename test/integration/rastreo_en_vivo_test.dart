// Pruebas de integración de la visualización de ubicación en tiempo real
// (SCRUM-129): la pantalla de entrenamiento completa, con cronómetro,
// posición en vivo, mapa y registro de puntos trabajando juntos. Solo se
// reemplaza lo que depende del dispositivo (GPS, reloj, tiles, Supabase).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/recorrido.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/controles_entrenamiento.dart';
import 'package:traza/widgets/cronometro_entrenamiento.dart';
import 'package:traza/widgets/mapa_entrenamiento.dart';
import 'package:traza/widgets/mapa_recorrido.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

void main() {
  late RelojFalso reloj;
  late FuenteUbicacionFalsa gps;
  late RepositorioPuntosGpsFalso supabase;
  late ProviderContainer container;

  const entrenamientoId = 'entrenamiento-abc';

  setUp(() {
    reloj = RelojFalso();
    gps = FuenteUbicacionFalsa();
    supabase = RepositorioPuntosGpsFalso();
    addTearDown(() => gps.cerrar());
    container = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(reloj.call),
        fuenteUbicacionProvider.overrideWithValue(gps),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        repositorioPuntosGpsProvider.overrideWithValue(supabase),
        entrenamientoActualProvider.overrideWithValue(entrenamientoId),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> entrarAlEntrenamiento(
    WidgetTester tester, {
    void Function(Duration)? onFinalizar,
    VoidCallback? onCancelar,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: TrackingScreen(
            nombreActividad: 'Correr',
            onFinalizar: onFinalizar,
            onCancelar: onCancelar,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// El usuario se desplaza: pasa [cuanto] tiempo y llega una lectura.
  Future<void> avanzar(
    WidgetTester tester, {
    required double latitud,
    required double longitud,
    Duration cuanto = const Duration(seconds: 5),
    double? precisionMetros = 8,
    Duration antiguedad = Duration.zero,
  }) async {
    reloj.avanzar(cuanto);
    gps.emitir(PuntoGps(
      latitud: latitud,
      longitud: longitud,
      capturadoEn: reloj().subtract(antiguedad),
      precisionMetros: precisionMetros,
    ));
    await tester.pump(cuanto);
    await tester.pump();
  }

  Future<void> pulsar(WidgetTester tester, Key boton) async {
    await tester.tap(find.byKey(boton));
    await tester.pump();
    await tester.pump();
  }

  String tiempo(WidgetTester tester) => tester
      .widget<Text>(find.byKey(CronometroEntrenamiento.claveTiempo))
      .data!;

  LatLng marcador(WidgetTester tester) => tester
      .widget<MarkerLayer>(find.byType(MarkerLayer))
      .markers
      .single
      .point;

  MapController camara(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  Recorrido recorrido() => container.read(recorridoProvider);

  void detener() => container.read(cronometroProvider.notifier).detener();

  testWidgets(
      'un entrenamiento completo: buscar señal, correr, pausar, reanudar '
      'y finalizar con el recorrido sincronizado', (tester) async {
    Duration? duracionReportada;
    await entrarAlEntrenamiento(
      tester,
      onFinalizar: (d) => duracionReportada = d,
    );

    // Al entrar: cronómetro en cero, GPS abierto, sin señal todavía.
    expect(tiempo(tester), '00:00:00');
    expect(gps.suscripcionesAbiertas, 1);
    expect(find.text('Buscando tu ubicación...'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);

    // Primer fix: aparece el mapa centrado y la píldora se enciende.
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);
    expect(find.byKey(MapaEntrenamiento.claveNota), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(marcador(tester), const LatLng(6.2311, -75.6105));
    expect(camara(tester).camera.center, const LatLng(6.2311, -75.6105));
    expect(tiempo(tester), '00:00:05');

    // El usuario corre: marcador y cámara lo siguen, el recorrido crece.
    await avanzar(tester, latitud: 6.2314, longitud: -75.6108);
    await avanzar(tester, latitud: 6.2317, longitud: -75.6112);
    expect(marcador(tester), const LatLng(6.2317, -75.6112));
    expect(camara(tester).camera.center, const LatLng(6.2317, -75.6112));
    expect(recorrido().puntos.length, 3);
    expect(tiempo(tester), '00:00:15');
    expect(supabase.lotes, isEmpty, reason: 'nada se sube durante la ruta');

    // Pausa: el tiempo se congela, la posición se sigue viendo pero no
    // se registra.
    await pulsar(tester, ControlesEntrenamiento.clavePausar);
    expect(find.text('EN PAUSA'), findsOneWidget);
    await avanzar(
      tester,
      latitud: 6.2400,
      longitud: -75.6200,
      cuanto: const Duration(minutes: 2),
    );
    expect(tiempo(tester), '00:00:15');
    expect(marcador(tester), const LatLng(6.2400, -75.6200));
    expect(recorrido().puntos.length, 3);

    // Reanudar: sigue contando y registrando desde donde iba.
    await pulsar(tester, ControlesEntrenamiento.clavePausar);
    expect(find.text('TIEMPO'), findsOneWidget);
    await avanzar(tester, latitud: 6.2319, longitud: -75.6117);
    expect(tiempo(tester), '00:00:20');
    expect(recorrido().puntos.length, 4);

    // Finalizar: se detiene, se reporta el tiempo y el lote va completo
    // y en orden, sin el punto capturado en pausa.
    await pulsar(tester, ControlesEntrenamiento.claveFinalizar);
    expect(duracionReportada, const Duration(seconds: 20));
    expect(container.read(cronometroProvider).estaEnCurso, isFalse);
    expect(recorrido().sincronizacion, EstadoSincronizacion.completada);
    expect(supabase.lotes.length, 1);
    expect(supabase.lotes.single.entrenamientoId, entrenamientoId);
    expect(
      supabase.lotes.single.puntos.map((p) => (p.latitud, p.longitud)),
      [
        (6.2311, -75.6105),
        (6.2314, -75.6108),
        (6.2317, -75.6112),
        (6.2319, -75.6117),
      ],
    );

    // Tras finalizar ya no entra nada más.
    await avanzar(tester, latitud: 6.2330, longitud: -75.6130);
    expect(tiempo(tester), '00:00:20');
    expect(recorrido().puntos.length, 4);
  });

  testWidgets('las lecturas imprecisas o viejas no llegan ni al mapa ni '
      'al recorrido', (tester) async {
    await entrarAlEntrenamiento(tester);

    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);

    // Fix bajo techo: 200 m de error.
    await avanzar(
      tester,
      latitud: 6.9000,
      longitud: -75.9000,
      precisionMetros: 200,
    );
    // Última posición conocida de hace 10 minutos.
    await avanzar(
      tester,
      latitud: 6.8000,
      longitud: -75.8000,
      antiguedad: const Duration(minutes: 10),
    );
    // Sin precisión reportada: se acepta.
    await avanzar(
      tester,
      latitud: 6.2314,
      longitud: -75.6108,
      precisionMetros: null,
    );

    expect(marcador(tester), const LatLng(6.2314, -75.6108));
    expect(
      recorrido().puntos.map((p) => p.latitud),
      [6.2311, 6.2314],
    );

    detener();
  });

  testWidgets('descartar el entrenamiento cierra el GPS y no sube nada',
      (tester) async {
    var cancelado = false;
    await entrarAlEntrenamiento(tester, onCancelar: () => cancelado = true);
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);
    await avanzar(tester, latitud: 6.2314, longitud: -75.6108);
    expect(recorrido().puntos.length, 2);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar este entrenamiento?'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(cancelado, isTrue);
    expect(supabase.lotes, isEmpty);
    expect(tiempo(tester), '00:00:00');

    // Al salir de la pantalla (el ProviderScope de la app sigue vivo, como
    // en main.dart) se suelta el GPS.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    expect(gps.suscripcionesAbiertas, 0);
  });

  testWidgets('"seguir entrenando" en el diálogo no interrumpe nada',
      (tester) async {
    await entrarAlEntrenamiento(tester);
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seguir entrenando'));
    await tester.pumpAndSettle();

    await avanzar(tester, latitud: 6.2314, longitud: -75.6108);
    expect(container.read(cronometroProvider).estaEnCurso, isTrue);
    expect(recorrido().puntos.length, 2);

    detener();
  });

  testWidgets('si Supabase falla al finalizar, el recorrido no se pierde '
      'y se avisa', (tester) async {
    await entrarAlEntrenamiento(tester);
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);
    await avanzar(tester, latitud: 6.2314, longitud: -75.6108);
    supabase.fallar = true;

    await pulsar(tester, ControlesEntrenamiento.claveFinalizar);

    expect(find.textContaining('no se pudo guardar'), findsOneWidget);
    expect(recorrido().sincronizacion, EstadoSincronizacion.fallida);
    expect(recorrido().puntos.length, 2);

    // Con red de nuevo, el mismo lote se puede reenviar completo.
    supabase.fallar = false;
    final ok = await container.read(recorridoProvider.notifier).sincronizar();
    expect(ok, isTrue);
    expect(supabase.lotes.single.puntos.length, 2);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('sin entrenamiento creado (SCRUM-45 pendiente) la actividad '
      'funciona igual y no toca Supabase', (tester) async {
    container = ProviderContainer(
      overrides: [
        relojProvider.overrideWithValue(reloj.call),
        fuenteUbicacionProvider.overrideWithValue(gps),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        repositorioPuntosGpsProvider.overrideWithValue(supabase),
        entrenamientoActualProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    await entrarAlEntrenamiento(tester, onFinalizar: (_) {});
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);
    await avanzar(tester, latitud: 6.2314, longitud: -75.6108);

    expect(find.byKey(MapaRecorrido.claveMarcador), findsOneWidget);
    expect(recorrido().puntos.length, 2);

    await pulsar(tester, ControlesEntrenamiento.claveFinalizar);

    expect(supabase.lotes, isEmpty);
    expect(recorrido().sincronizacion, EstadoSincronizacion.completada);
  });
}
