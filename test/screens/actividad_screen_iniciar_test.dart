import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/screens/home/actividad_screen.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/permisos_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/tipos_actividad_service.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/requiere_permiso_ubicacion.dart';
import 'package:traza/widgets/ventana_permiso_salud.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/rutas_repository_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Pruebas del inicio del entrenamiento desde la pantalla de inicio: el toque
/// que arranca la actividad (SCRUM-96), los permisos que hacen falta antes
/// (SCRUM-97) y lo que se le dice al usuario cuando no se puede (SCRUM-100).
///
/// En rutas oficiales, etapa 3, la pantalla también puede llegar con la ruta
/// que el corredor eligió en el detalle: la muestra y el entrenamiento nace
/// asociado a ella, con el mismo flujo de permisos de siempre.
void main() {
  late _MockPermisosService permisos;
  late _EntrenamientosFalso entrenamientos;
  late FuenteUbicacionFalsa gps;
  late ProviderContainer container;

  setUp(() {
    permisos = _MockPermisosService();
    entrenamientos = _EntrenamientosFalso();
    gps = FuenteUbicacionFalsa();
    addTearDown(() => gps.cerrar());
    // Con la salud concedida no sale su ventana. Lo que pasa sin ella se
    // prueba en su propio grupo (SCRUM-131).
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  void ubicacionEsta(EstadoPermiso estado) {
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => estado);
  }

  /// Lo que responde el usuario a la ventana del sistema.
  void alPedirUbicacionResponde(EstadoPermiso estado) {
    when(() => permisos.solicitarUbicacion()).thenAnswer((_) async => estado);
  }

  /// Abre la pantalla de inicio del entrenamiento. Con [ruta], como la abre
  /// "Correr esta ruta" desde el detalle (rutas oficiales, etapa 3).
  ///
  /// La ruta viaja en `extra`, por [ActividadScreen.desdeRuta], que es lo
  /// mismo que hace `main.dart`. [extra] permite mandar otra cosa.
  Future<void> abrirInicio(
    WidgetTester tester, {
    Ruta? ruta,
    Object? extra,
  }) async {
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
        fuenteUbicacionProvider.overrideWithValue(gps),
        tiposActividadRepositoryProvider.overrideWithValue(
          const _CatalogoFalso(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/actividad',
      initialExtra: extra ?? ruta,
      routes: [
        GoRoute(
          path: '/actividad',
          builder: (_, state) => ActividadScreen.desdeRuta(state),
        ),
        GoRoute(
          path: '/tracking',
          builder: (_, _) =>
              const Scaffold(body: Text('Entrenamiento en curso')),
        ),
        GoRoute(
          path: '/permisos',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Permisos')),
        ),
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada')),
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

  Future<void> tocarIniciar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar actividad'));
    await tester.pumpAndSettle();
  }

  bool estaEnElEntrenamiento(WidgetTester tester) =>
      find.text('Entrenamiento en curso').evaluate().isNotEmpty;

  group('salida de la pantalla', () {
    testWidgets('la flecha vuelve a la portada sin arrancar nada', (
      tester,
    ) async {
      await abrirInicio(tester);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.text('Portada'), findsOneWidget);
      expect(entrenamientos.creados, isEmpty);
    });
  });

  group('con el permiso de ubicación concedido', () {
    setUp(() => ubicacionEsta(EstadoPermiso.concedido));

    testWidgets('un solo toque crea el entrenamiento y abre la actividad', (
      tester,
    ) async {
      await abrirInicio(tester);

      await tocarIniciar(tester);

      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
      expect(container.read(entrenamientoActualProvider), 'entrenamiento-1');
      // La actividad queda fija mientras dura el entrenamiento (SCRUM-94).
      expect(container.read(actividadIniciadaProvider), isTrue);
    });

    testWidgets('no vuelve a pedir un permiso que ya está concedido', (
      tester,
    ) async {
      await abrirInicio(tester);

      await tocarIniciar(tester);

      verifyNever(() => permisos.solicitarUbicacion());
    });

    testWidgets('crea el entrenamiento de la actividad elegida', (
      tester,
    ) async {
      await abrirInicio(tester);
      container
          .read(actividadSeleccionadaProvider.notifier)
          .seleccionar(const TipoActividad(id: 'id-trote', nombre: 'Trote'));
      await tester.pumpAndSettle();

      await tocarIniciar(tester);

      expect(entrenamientos.creados, ['id-trote']);
    });

    testWidgets('dos toques seguidos crean un solo entrenamiento', (
      tester,
    ) async {
      await abrirInicio(tester);

      // Los dos toques, sin dejar que la pantalla se actualice entre medias:
      // así se comprueba que el segundo no llega a crear nada (SCRUM-96).
      final boton = find.widgetWithText(FilledButton, 'Iniciar actividad');
      await tester.tap(boton);
      await tester.tap(boton);
      await tester.pumpAndSettle();

      expect(entrenamientos.creados, hasLength(1));
      expect(estaEnElEntrenamiento(tester), isTrue);
    });
  });

  group('la actividad en curso se nota en la pantalla (SCRUM-98)', () {
    setUp(() => ubicacionEsta(EstadoPermiso.concedido));

    testWidgets('al iniciar se pasa a la pantalla del entrenamiento', (
      tester,
    ) async {
      await abrirInicio(tester);
      expect(estaEnElEntrenamiento(tester), isFalse);

      await tocarIniciar(tester);

      expect(estaEnElEntrenamiento(tester), isTrue);
    });

    testWidgets('mientras dura, el inicio avisa y no deja cambiar de '
        'actividad', (tester) async {
      await abrirInicio(tester);
      await tocarIniciar(tester);

      // Se vuelve al inicio sin terminar la actividad, como haria el sistema
      // al restaurar la app.
      container
          .read(actividadSeleccionadaProvider.notifier)
          .seleccionar(const TipoActividad(id: 'id-trote', nombre: 'Trote'));

      // La actividad elegida no cambia: hay un entrenamiento en curso
      // (SCRUM-94).
      expect(container.read(actividadSeleccionadaProvider)?.nombre, 'Correr');
      expect(container.read(actividadIniciadaProvider), isTrue);
    });
  });

  group('cuando falta el permiso de ubicación (SCRUM-97)', () {
    testWidgets('lo pide al tocar iniciar y, si lo conceden, arranca igual', (
      tester,
    ) async {
      ubicacionEsta(EstadoPermiso.denegado);
      alPedirUbicacionResponde(EstadoPermiso.concedido);
      await abrirInicio(tester);

      await tocarIniciar(tester);

      verify(() => permisos.solicitarUbicacion()).called(1);
      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
    });

    testWidgets('si lo niegan no crea el entrenamiento y explica por qué', (
      tester,
    ) async {
      ubicacionEsta(EstadoPermiso.denegado);
      alPedirUbicacionResponde(EstadoPermiso.denegado);
      await abrirInicio(tester);

      await tocarIniciar(tester);

      expect(entrenamientos.creados, isEmpty);
      expect(estaEnElEntrenamiento(tester), isFalse);
      expect(find.text(RequierePermisoUbicacion.mensaje), findsOneWidget);
      // Nada quedó a medias: se puede volver a intentar.
      expect(container.read(actividadIniciadaProvider), isFalse);
      expect(container.read(entrenamientoActualProvider), isNull);
    });

    testWidgets('bloqueado: no lo pide en vano y lleva a los ajustes', (
      tester,
    ) async {
      ubicacionEsta(EstadoPermiso.bloqueado);
      await abrirInicio(tester);

      await tocarIniciar(tester);

      // El sistema ya no muestra su ventana: pedirlo otra vez no haría nada.
      verifyNever(() => permisos.solicitarUbicacion());
      expect(entrenamientos.creados, isEmpty);
      expect(find.text('Pantalla Permisos'), findsOneWidget);
    });

    testWidgets('el botón vuelve a quedar disponible tras negarlo', (
      tester,
    ) async {
      ubicacionEsta(EstadoPermiso.denegado);
      alPedirUbicacionResponde(EstadoPermiso.denegado);
      await abrirInicio(tester);
      await tocarIniciar(tester);

      alPedirUbicacionResponde(EstadoPermiso.concedido);
      await tocarIniciar(tester);

      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
    });
  });

  group('sin el permiso de datos de salud (SCRUM-131)', () {
    setUp(() {
      ubicacionEsta(EstadoPermiso.concedido);
      when(
        () => permisos.estadoSalud(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
    });

    bool hayVentana() =>
        find.text(VentanaPermisoSalud.titulo).evaluate().isNotEmpty;

    /// Toca "Iniciar actividad" y espera a que salga la ventana. Sin
    /// `pumpAndSettle`: mientras la ventana espera la respuesta, el botón
    /// muestra su indicador de carga y la pantalla nunca queda quieta.
    Future<void> tocarIniciarHastaLaVentana(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar actividad'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('ofrece la ventana antes de crear el entrenamiento', (
      tester,
    ) async {
      await abrirInicio(tester);

      await tocarIniciarHastaLaVentana(tester);

      expect(hayVentana(), isTrue);
      expect(entrenamientos.creados, isEmpty);
      expect(estaEnElEntrenamiento(tester), isFalse);
    });

    testWidgets('"Aceptar" pide el permiso y arranca', (tester) async {
      when(
        () => permisos.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await abrirInicio(tester);
      await tocarIniciarHastaLaVentana(tester);

      await tester.tap(find.text(VentanaPermisoSalud.aceptar));
      await tester.pumpAndSettle();

      verify(() => permisos.solicitarSalud()).called(1);
      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
      expect(container.read(permisosProvider).saludOmitida, isFalse);
    });

    testWidgets('si lo niega arranca igual, sin datos de salud', (
      tester,
    ) async {
      when(
        () => permisos.solicitarSalud(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      await abrirInicio(tester);
      await tocarIniciarHastaLaVentana(tester);

      await tester.tap(find.text(VentanaPermisoSalud.aceptar));
      await tester.pumpAndSettle();

      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
      expect(container.read(permisosProvider).saludOmitida, isTrue);
    });

    testWidgets('"Continuar sin datos de salud" arranca sin pedirlo', (
      tester,
    ) async {
      await abrirInicio(tester);
      await tocarIniciarHastaLaVentana(tester);

      await tester.tap(find.text(VentanaPermisoSalud.continuarSin));
      await tester.pumpAndSettle();

      verifyNever(() => permisos.solicitarSalud());
      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
      expect(container.read(permisosProvider).saludOmitida, isTrue);
    });

    testWidgets('cerrar la ventana con "atrás" no arranca nada', (
      tester,
    ) async {
      await abrirInicio(tester);
      await tocarIniciarHastaLaVentana(tester);

      Navigator.of(tester.element(find.byType(VentanaPermisoSalud))).pop();
      await tester.pumpAndSettle();

      expect(hayVentana(), isFalse);
      expect(entrenamientos.creados, isEmpty);
      expect(estaEnElEntrenamiento(tester), isFalse);
      expect(container.read(actividadIniciadaProvider), isFalse);
      // El botón queda libre para volver a intentarlo.
      await tocarIniciarHastaLaVentana(tester);
      expect(hayVentana(), isTrue);
    });
  });

  group('correr una ruta oficial (rutas oficiales, etapa 3)', () {
    final estadio = rutaDePrueba(
      id: 'ruta-estadio',
      nombre: 'Vuelta al estadio',
      estado: EstadoRuta.publicada,
      trazado: const [
        PuntoRuta(latitud: 6.2442, longitud: -75.5812),
        PuntoRuta(latitud: 6.2450, longitud: -75.5800),
      ],
    );

    final tarjetaRuta = find.byKey(ActividadScreen.claveRutaElegida);

    Finder enLaTarjeta(String texto) =>
        find.descendant(of: tarjetaRuta, matching: find.textContaining(texto));

    testWidgets('con una ruta, la muestra en una tarjeta: "Vas a correr" y su '
        'nombre', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      await abrirInicio(tester, ruta: estadio);

      expect(tarjetaRuta, findsOneWidget);
      expect(enLaTarjeta('Vas a correr'), findsOneWidget);
      expect(enLaTarjeta('Vuelta al estadio'), findsOneWidget);
      // El resto de la pantalla no cambia: se elige la actividad igual.
      expect(
        find.widgetWithText(FilledButton, 'Iniciar actividad'),
        findsOneWidget,
      );
    });

    testWidgets('si la navegación trae otra cosa en extra, no falla: abre '
        'como un entrenamiento libre', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      await abrirInicio(tester, extra: 'no es una ruta');

      expect(tester.takeException(), isNull);
      expect(tarjetaRuta, findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Iniciar actividad'),
        findsOneWidget,
      );
    });

    testWidgets('sin ruta no hay tarjeta de ruta elegida', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      await abrirInicio(tester);

      expect(tarjetaRuta, findsNothing);
      expect(find.textContaining('Vas a correr'), findsNothing);
    });

    testWidgets('al iniciar, el entrenamiento se crea asociado a la ruta y con '
        'la actividad de los chips', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      await abrirInicio(tester, ruta: estadio);
      container
          .read(actividadSeleccionadaProvider.notifier)
          .seleccionar(const TipoActividad(id: 'id-trote', nombre: 'Trote'));
      await tester.pumpAndSettle();

      await tocarIniciar(tester);

      expect(entrenamientos.creados, ['id-trote']);
      expect(entrenamientos.rutas, ['ruta-estadio']);
      expect(estaEnElEntrenamiento(tester), isTrue);
      // La ruta queda en curso para que el tracking la dibuje como guía.
      expect(container.read(rutaEnCursoProvider)?.id, 'ruta-estadio');
      expect(container.read(rutaEnCursoProvider)?.trazado, estadio.trazado);
    });

    testWidgets('sin ruta, el entrenamiento se crea sin rutaId, como hasta '
        'ahora', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      await abrirInicio(tester);

      await tocarIniciar(tester);

      expect(entrenamientos.creados, ['id-correr']);
      expect(entrenamientos.rutas, [null]);
      expect(container.read(rutaEnCursoProvider), isNull);
    });

    testWidgets('con ruta, si falta el permiso de ubicación lo pide antes de '
        'crear nada, igual que sin ruta', (tester) async {
      ubicacionEsta(EstadoPermiso.denegado);
      alPedirUbicacionResponde(EstadoPermiso.concedido);
      await abrirInicio(tester, ruta: estadio);

      await tocarIniciar(tester);

      verify(() => permisos.solicitarUbicacion()).called(1);
      expect(entrenamientos.rutas, ['ruta-estadio']);
      expect(estaEnElEntrenamiento(tester), isTrue);
    });

    testWidgets('con ruta, si niegan la ubicación no crea el entrenamiento ni '
        'deja la ruta en curso', (tester) async {
      ubicacionEsta(EstadoPermiso.denegado);
      alPedirUbicacionResponde(EstadoPermiso.denegado);
      await abrirInicio(tester, ruta: estadio);

      await tocarIniciar(tester);

      expect(entrenamientos.creados, isEmpty);
      expect(find.text(RequierePermisoUbicacion.mensaje), findsOneWidget);
      expect(container.read(rutaEnCursoProvider), isNull);
    });

    testWidgets('con ruta, sin el permiso de salud ofrece la ventana antes de '
        'crear el entrenamiento, igual que sin ruta', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      when(
        () => permisos.estadoSalud(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      await abrirInicio(tester, ruta: estadio);

      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar actividad'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(VentanaPermisoSalud.titulo), findsOneWidget);
      expect(entrenamientos.creados, isEmpty);

      await tester.tap(find.text(VentanaPermisoSalud.continuarSin));
      await tester.pumpAndSettle();

      expect(entrenamientos.rutas, ['ruta-estadio']);
      expect(estaEnElEntrenamiento(tester), isTrue);
    });

    testWidgets('con ruta, si el entrenamiento no se puede crear lo avisa y '
        'no deja la ruta en curso', (tester) async {
      ubicacionEsta(EstadoPermiso.concedido);
      entrenamientos.error = StateError('sin red');
      await abrirInicio(tester, ruta: estadio);

      await tocarIniciar(tester);

      expect(find.text(InicioEntrenamiento.noSePudo), findsOneWidget);
      expect(estaEnElEntrenamiento(tester), isFalse);
      expect(container.read(rutaEnCursoProvider), isNull);
      // La ruta sigue elegida: se puede volver a intentar.
      expect(tarjetaRuta, findsOneWidget);
    });
  });

  group('cuando el entrenamiento no se puede crear (SCRUM-100)', () {
    setUp(() => ubicacionEsta(EstadoPermiso.concedido));

    testWidgets('lo avisa y se queda en el inicio', (tester) async {
      entrenamientos.error = StateError('sin red');
      await abrirInicio(tester);

      await tocarIniciar(tester);

      expect(estaEnElEntrenamiento(tester), isFalse);
      expect(find.text('No se pudo iniciar el entrenamiento'), findsOneWidget);
      expect(container.read(actividadIniciadaProvider), isFalse);
    });

    testWidgets('con la ubicación del teléfono apagada avisa y no crea nada', (
      tester,
    ) async {
      gps.servicio = false;
      await abrirInicio(tester);

      await tocarIniciar(tester);

      expect(find.text(InicioEntrenamiento.ubicacionApagada), findsOneWidget);
      expect(entrenamientos.creados, isEmpty);
      expect(estaEnElEntrenamiento(tester), isFalse);
    });

    testWidgets('tras el aviso se puede reintentar', (tester) async {
      entrenamientos.error = StateError('sin red');
      await abrirInicio(tester);
      await tocarIniciar(tester);

      entrenamientos.error = null;
      await tocarIniciar(tester);

      expect(entrenamientos.creados, ['id-correr']);
      expect(estaEnElEntrenamiento(tester), isTrue);
    });
  });
}

/// Entrenamientos en memoria: anota cada creación y, si la prueba lo indica,
/// falla o se queda esperando.
class _EntrenamientosFalso implements EntrenamientoRepository {
  final creados = <String>[];

  /// `ruta_id` de cada entrenamiento creado, en el mismo orden que
  /// [creados]: null si se creó sin ruta (rutas oficiales, etapa 3).
  final rutas = <String?>[];

  Object? error;

  @override
  Future<String> crear({
    required String tipoActividadId,
    String? rutaId,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    creados.add(tipoActividadId);
    rutas.add(rutaId);
    return 'entrenamiento-${creados.length}';
  }

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) async {}

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) => throw UnimplementedError('El inicio no cierra entrenamientos');

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError('El inicio no lee entrenamientos');
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
