import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/screens/home/inicio_screen.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/tipos_actividad_service.dart';
import 'package:traza/widgets/requiere_permiso_ubicacion.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Pruebas del inicio del entrenamiento desde la pantalla de inicio: el toque
/// que arranca la actividad (SCRUM-96), los permisos que hacen falta antes
/// (SCRUM-97) y lo que se le dice al usuario cuando no se puede (SCRUM-100).
void main() {
  late _MockPermisosService permisos;
  late _EntrenamientosFalso entrenamientos;
  late ProviderContainer container;

  setUp(() {
    permisos = _MockPermisosService();
    entrenamientos = _EntrenamientosFalso();
    // La salud no bloquea el inicio: se deja siempre sin conceder.
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  void ubicacionEsta(EstadoPermiso estado) {
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => estado);
  }

  /// Lo que responde el usuario a la ventana del sistema.
  void alPedirUbicacionResponde(EstadoPermiso estado) {
    when(() => permisos.solicitarUbicacion()).thenAnswer((_) async => estado);
  }

  Future<void> abrirInicio(WidgetTester tester) async {
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
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const InicioScreen()),
        GoRoute(
          path: '/tracking',
          builder: (_, _) =>
              const Scaffold(body: Text('Entrenamiento en curso')),
        ),
        GoRoute(
          path: '/permisos',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Permisos')),
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
      container.read(actividadSeleccionadaProvider.notifier)
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

  group('cuando el entrenamiento no se puede crear (SCRUM-100)', () {
    setUp(() => ubicacionEsta(EstadoPermiso.concedido));

    testWidgets('lo avisa y se queda en el inicio', (tester) async {
      entrenamientos.error = StateError('sin red');
      await abrirInicio(tester);

      await tocarIniciar(tester);

      expect(estaEnElEntrenamiento(tester), isFalse);
      expect(
        find.text('No se pudo iniciar el entrenamiento. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(container.read(actividadIniciadaProvider), isFalse);
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

  Object? error;

  @override
  Future<String> crear({required String tipoActividadId}) async {
    final error = this.error;
    if (error != null) throw error;
    creados.add(tipoActividadId);
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
