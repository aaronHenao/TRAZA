import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/features/actividad/data/tipos_actividad_repository.dart';
import 'package:traza/features/actividad/domain/tipo_actividad.dart';
import 'package:traza/features/actividad/presentation/actividad_providers.dart';
import 'package:traza/features/actividad/presentation/inicio_screen.dart';
import 'package:traza/features/actividad/presentation/widgets/chips_tipo_actividad.dart';
import 'package:traza/features/actividad/presentation/widgets/seccion_iniciar_entrenamiento.dart';

/// Pruebas de la pantalla de inicio: su diseño (SCRUM-91) y los chips de tipo
/// de actividad (SCRUM-92).
void main() {
  group('diseño de la pantalla', () {
    testWidgets('muestra la cabecera del prototipo', (tester) async {
      await _montar(tester);

      expect(find.text('Listo para entrenar'), findsOneWidget);
      expect(find.text('Elige tu actividad y comienza'), findsOneWidget);
    });

    testWidgets('muestra la sección para iniciar el entrenamiento', (
      tester,
    ) async {
      await _montar(tester);

      expect(
        find.text(
          'Al iniciar verás el cronómetro, tu ubicación y la distancia '
          'recorrida en tiempo real.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Iniciar actividad'),
        findsOneWidget,
      );
    });

    testWidgets('el historial queda deshabilitado hasta que exista su '
        'pantalla', (tester) async {
      await _montar(tester);

      expect(find.byTooltip('Historial'), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    });

    testWidgets('"Iniciar actividad" sigue deshabilitado hasta que se conecte '
        'en SCRUM-96', (tester) async {
      await _montar(tester);

      expect(_botonIniciar(tester).onPressed, isNull);
    });
  });

  group('chips de tipo de actividad', () {
    testWidgets('muestra un chip por cada tipo del catálogo', (tester) async {
      await _montar(tester);

      expect(_chip('Correr'), findsOneWidget);
      expect(_chip('Trote'), findsOneWidget);
      expect(_chip('Caminar'), findsOneWidget);
    });

    testWidgets('arranca con el primer tipo marcado, como en el prototipo', (
      tester,
    ) async {
      await _montar(tester);

      expect(_seleccionada(tester)?.nombre, 'Correr');
      expect(_enLaSeccion('Correr'), findsOneWidget);
    });

    testWidgets('al tocar un chip lo guarda como la actividad a realizar', (
      tester,
    ) async {
      await _montar(tester);

      await tester.tap(_chip('Trote'));
      await tester.pump();

      expect(_seleccionada(tester)?.nombre, 'Trote');
      expect(_enLaSeccion('Trote'), findsOneWidget);
      expect(_enLaSeccion('Correr'), findsNothing);
    });

    testWidgets('elegir otro chip reemplaza la selección anterior', (
      tester,
    ) async {
      await _montar(tester);

      await tester.tap(_chip('Trote'));
      await tester.pump();
      await tester.tap(_chip('Caminar'));
      await tester.pump();

      expect(_seleccionada(tester)?.nombre, 'Caminar');
      expect(_enLaSeccion('Caminar'), findsOneWidget);
      expect(_enLaSeccion('Trote'), findsNothing);
    });

    testWidgets('la actividad elegida queda disponible con su id para el '
        'flujo de inicio', (tester) async {
      await _montar(tester);

      await tester.tap(_chip('Caminar'));
      await tester.pump();

      // El flujo de inicio (SCRUM-93 y SCRUM-96) necesita el id para crear
      // el entrenamiento en `entrenamientos.tipo_actividad_id`.
      expect(_seleccionada(tester)?.id, 'id-caminar');
    });

    testWidgets('con el catálogo vacío lo avisa y no hay actividad elegida', (
      tester,
    ) async {
      await _montar(tester, repositorio: _RepositorioFalso([]));

      expect(find.text('No hay actividades disponibles.'), findsOneWidget);
      expect(_seleccionada(tester), isNull);
      expect(_enLaSeccion('Ninguna actividad seleccionada'), findsOneWidget);
    });

    testWidgets('si el catálogo falla lo avisa y permite reintentar', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso()..error = Exception('sin red');
      await _montar(tester, repositorio: repositorio);

      expect(find.text('No pudimos cargar las actividades.'), findsOneWidget);
      expect(_enLaSeccion('Ninguna actividad seleccionada'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(_chip('Correr'), findsOneWidget);
      expect(_seleccionada(tester)?.nombre, 'Correr');
    });
  });

  group('sección para iniciar el entrenamiento', () {
    testWidgets('con una actividad la muestra y habilita el botón', (
      tester,
    ) async {
      var iniciado = false;
      await _montar(
        tester,
        pantalla: Scaffold(
          body: SeccionIniciarEntrenamiento(
            actividad: 'Correr',
            onIniciar: () => iniciado = true,
          ),
        ),
      );

      expect(find.text('Correr'), findsOneWidget);
      expect(find.text('Ninguna actividad seleccionada'), findsNothing);

      await tester.tap(find.text('Iniciar actividad'));
      expect(iniciado, isTrue);
    });

    testWidgets('con actividad pero sin acción conectada sigue deshabilitado', (
      tester,
    ) async {
      await _montar(
        tester,
        pantalla: const Scaffold(
          body: SeccionIniciarEntrenamiento(
            actividad: 'Correr',
            onIniciar: null,
          ),
        ),
      );

      expect(_botonIniciar(tester).onPressed, isNull);
    });
  });
}

const _catalogo = [
  TipoActividad(id: 'id-correr', nombre: 'Correr'),
  TipoActividad(id: 'id-trote', nombre: 'Trote'),
  TipoActividad(id: 'id-caminar', nombre: 'Caminar'),
];

/// Repositorio de mentira: devuelve el catálogo que se le configure o finge un
/// fallo.
class _RepositorioFalso implements TiposActividadRepository {
  _RepositorioFalso([this.tipos = _catalogo]);

  final List<TipoActividad> tipos;
  Object? error;

  @override
  Future<List<TipoActividad>> cargar() async {
    if (error case final error?) throw error;
    return tipos;
  }
}

Future<void> _montar(
  WidgetTester tester, {
  TiposActividadRepository? repositorio,
  Widget pantalla = const InicioScreen(),
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tiposActividadRepositoryProvider.overrideWithValue(
          repositorio ?? _RepositorioFalso(),
        ),
      ],
      child: MaterialApp(home: pantalla),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _chip(String nombre) => find.descendant(
  of: find.byType(ChipsTipoActividad),
  matching: find.text(nombre),
);

Finder _enLaSeccion(String texto) => find.descendant(
  of: find.byType(SeccionIniciarEntrenamiento),
  matching: find.text(texto),
);

/// La actividad a realizar, leída del [ProviderScope] que monta la pantalla.
TipoActividad? _seleccionada(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(InicioScreen)),
).read(actividadSeleccionadaProvider);

FilledButton _botonIniciar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));
