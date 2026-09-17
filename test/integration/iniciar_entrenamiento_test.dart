// Pruebas de integración del inicio de la actividad (SCRUM-101): desde la
// pantalla de inicio hasta el entrenamiento en curso, con las mismas rutas y
// los mismos guardas de permisos que arma `main.dart`.
//
// Solo se reemplaza lo que depende del dispositivo o de la red: permisos,
// GPS, tiles, reloj y Supabase.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/screens/home/inicio_screen.dart';
import 'package:traza/screens/tracking/tracking_con_actividad_elegida.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/tipos_actividad_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/controles_entrenamiento.dart';
import 'package:traza/widgets/cronometro_entrenamiento.dart';
import 'package:traza/widgets/ofrece_permiso_salud.dart';
import 'package:traza/widgets/requiere_permiso_ubicacion.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/reloj_falso.dart';
import '../utiles/repositorio_puntos_gps_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

void main() {
  late _MockPermisosService permisos;
  late _EntrenamientosFalso entrenamientos;
  late FuenteUbicacionFalsa gps;
  late RepositorioPuntosGpsFalso puntosGps;
  late RelojFalso reloj;
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    permisos = _MockPermisosService();
    entrenamientos = _EntrenamientosFalso();
    gps = FuenteUbicacionFalsa();
    puntosGps = RepositorioPuntosGpsFalso();
    reloj = RelojFalso();
    addTearDown(() => gps.cerrar());

    // Camino feliz: ubicación concedida y un teléfono sin datos de salud, que
    // es opcional y no debe estorbar al iniciar.
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.noDisponible);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  Future<void> abrirApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    container = ProviderContainer(
      overrides: [
        permisosServiceProvider.overrideWithValue(permisos),
        permisosUsuarioRepositoryProvider.overrideWithValue(
          _PermisosUsuarioFalso(),
        ),
        entrenamientoRepositoryProvider.overrideWithValue(entrenamientos),
        tiposActividadRepositoryProvider.overrideWithValue(
          const _CatalogoFalso(),
        ),
        fuenteUbicacionProvider.overrideWithValue(gps),
        repositorioPuntosGpsProvider.overrideWithValue(puntosGps),
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        relojProvider.overrideWithValue(reloj.call),
      ],
    );
    addTearDown(container.dispose);

    router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const InicioScreen()),
        GoRoute(
          path: '/permisos',
          builder: (_, _) => const _Pantalla('Permisos'),
        ),
        // La misma cadena de guardas que monta main.dart.
        GoRoute(
          path: '/tracking',
          builder: (_, _) => const RequierePermisoUbicacion(
            child: OfrecePermisoSalud(child: TrackingConActividadElegida()),
          ),
        ),
        GoRoute(
          path: '/resumen',
          builder: (_, _) => const _Pantalla('Resumen'),
          routes: [
            GoRoute(
              path: ':entrenamientoId',
              builder: (_, _) => const _Pantalla('Resumen'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Toca "Iniciar actividad" y espera a que la navegación termine. Sin
  /// `pumpAndSettle`: con el entrenamiento en curso el cronómetro refresca
  /// sin parar y la pantalla nunca queda quieta.
  Future<void> tocarIniciar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar actividad'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// El usuario se desplaza: pasa el tiempo y llega una lectura del GPS.
  Future<void> avanzar(
    WidgetTester tester, {
    required double latitud,
    required double longitud,
  }) async {
    const cuanto = Duration(seconds: 5);
    reloj.avanzar(cuanto);
    gps.emitir(
      PuntoGps(
        latitud: latitud,
        longitud: longitud,
        capturadoEn: reloj(),
        precisionMetros: 8,
      ),
    );
    await tester.pump(cuanto);
    await tester.pump();
  }

  String tiempo(WidgetTester tester) => tester
      .widget<Text>(find.byKey(CronometroEntrenamiento.claveTiempo))
      .data!;

  String? ubicacion() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('un entrenamiento completo: elegir actividad, un toque, correr '
      'y finalizar', (tester) async {
    await abrirApp(tester);

    // Se elige Trote en los chips (SCRUM-92).
    await tester.tap(find.text('Trote'));
    await tester.pumpAndSettle();

    await tocarIniciar(tester);

    // La actividad arrancó: se creó el entrenamiento del tipo elegido y la
    // pantalla del entrenamiento está en pantalla (SCRUM-96, 98 y 99).
    expect(entrenamientos.creados, ['id-trote']);
    expect(find.byType(TrackingScreen), findsOneWidget);
    expect(find.text('Trote'), findsOneWidget);
    expect(tiempo(tester), '00:00:00');
    expect(container.read(entrenamientoActualProvider), 'entrenamiento-1');

    // Corre: el cronómetro avanza y el recorrido se registra en local.
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);
    await avanzar(tester, latitud: 6.2314, longitud: -75.6108);
    expect(tiempo(tester), '00:00:10');
    expect(container.read(recorridoProvider).puntos.length, 2);
    expect(puntosGps.lotes, isEmpty, reason: 'nada se sube durante la ruta');

    // Finaliza: los puntos se suben con el id del entrenamiento creado, la
    // fila se cierra y se pasa al resumen.
    await tester.tap(find.byKey(ControlesEntrenamiento.claveFinalizar));
    await tester.pumpAndSettle();

    expect(puntosGps.lotes.single.entrenamientoId, 'entrenamiento-1');
    expect(puntosGps.lotes.single.puntos.length, 2);
    expect(entrenamientos.cerrados, ['entrenamiento-1']);
    expect(ubicacion(), '/resumen/entrenamiento-1');
    // El siguiente entrenamiento empieza de cero.
    expect(container.read(entrenamientoActualProvider), isNull);
    expect(container.read(actividadIniciadaProvider), isFalse);
  });

  testWidgets('descartar cierra la fila y devuelve al inicio', (tester) async {
    await abrirApp(tester);
    await tocarIniciar(tester);
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(ubicacion(), '/inicio');
    expect(entrenamientos.cancelados, ['entrenamiento-1']);
    expect(puntosGps.lotes, isEmpty, reason: 'un descarte no guarda nada');
    // Se puede elegir otra actividad y volver a empezar (SCRUM-94).
    expect(container.read(actividadIniciadaProvider), isFalse);
    expect(container.read(entrenamientoActualProvider), isNull);
  });

  testWidgets('sin permiso de ubicación no se llega a crear el entrenamiento', (
    tester,
  ) async {
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    when(
      () => permisos.solicitarUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.denegado);
    await abrirApp(tester);

    await tocarIniciar(tester);

    expect(entrenamientos.creados, isEmpty);
    expect(ubicacion(), '/inicio');
    expect(find.text(RequierePermisoUbicacion.mensaje), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('con la ubicación del teléfono apagada tampoco', (tester) async {
    gps.servicio = false;
    await abrirApp(tester);

    await tocarIniciar(tester);

    expect(entrenamientos.creados, isEmpty);
    expect(ubicacion(), '/inicio');
    expect(find.text(InicioEntrenamiento.ubicacionApagada), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('dos entrenamientos seguidos no se pisan', (tester) async {
    await abrirApp(tester);

    await tocarIniciar(tester);
    await avanzar(tester, latitud: 6.2311, longitud: -75.6105);
    await tester.tap(find.byKey(ControlesEntrenamiento.claveFinalizar));
    await tester.pumpAndSettle();

    // Del resumen se vuelve al inicio para empezar otro.
    router.go('/inicio');
    await tester.pumpAndSettle();
    await tocarIniciar(tester);
    await avanzar(tester, latitud: 6.2400, longitud: -75.6200);

    expect(entrenamientos.creados, ['id-correr', 'id-correr']);
    expect(container.read(entrenamientoActualProvider), 'entrenamiento-2');
    // El recorrido del segundo empieza vacío, no arrastra el del primero.
    expect(container.read(recorridoProvider).puntos.length, 1);

    container.read(cronometroProvider.notifier).detener();
  });
}

class _Pantalla extends StatelessWidget {
  const _Pantalla(this.nombre);

  final String nombre;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(nombre));
}

/// Entrenamientos en memoria: anota lo que se crea, se cierra y se descarta.
class _EntrenamientosFalso implements EntrenamientoRepository {
  final creados = <String>[];
  final cerrados = <String>[];
  final cancelados = <String>[];

  @override
  Future<String> crear({required String tipoActividadId}) async {
    creados.add(tipoActividadId);
    return 'entrenamiento-${creados.length}';
  }

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) async {
    cerrados.add(entrenamientoId);
  }

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) async {
    cancelados.add(entrenamientoId);
  }

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError('El resumen llega con los datos ya puestos');
}

class _CatalogoFalso implements TiposActividadRepository {
  const _CatalogoFalso();

  @override
  Future<List<TipoActividad>> cargar() async => const [
    TipoActividad(id: 'id-correr', nombre: 'Correr'),
    TipoActividad(id: 'id-trote', nombre: 'Trote'),
  ];
}

class _PermisosUsuarioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}
