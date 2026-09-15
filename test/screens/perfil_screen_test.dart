import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/services/perfil_provider.dart';
import 'package:traza/screens/onboarding/perfil_screen.dart';
import 'package:traza/models/perfil_state.dart';
import 'package:traza/widgets/configuracion_valor_objetivo.dart';
import 'package:traza/screens/onboarding/permisos_screen.dart';

/// Pruebas de la pantalla de perfil: selección de objetivos (SCRUM-86), sus
/// valores (SCRUM-87 y SCRUM-88), el guardado (SCRUM-89) y la edición de los
/// que ya estaban configurados (SCRUM-90). La cobertura completa de la gestión
/// de objetivos llega en SCRUM-128.
void main() {
  testWidgets('muestra el estado vacío cuando no hay objetivos seleccionados', (
    tester,
  ) async {
    await _montarPerfil(tester);

    expect(find.text('Aún no has elegido objetivos'), findsOneWidget);
    expect(find.text('Distancia semanal'), findsOneWidget);
    expect(find.text('Frecuencia de entrenamiento'), findsOneWidget);
  });

  testWidgets('permite seleccionar varios objetivos a la vez', (tester) async {
    await _montarPerfil(tester);

    await tester.tap(find.text('Distancia semanal'));
    await tester.pump();

    expect(find.text('Aún no has elegido objetivos'), findsNothing);

    await tester.tap(find.text('Frecuencia de entrenamiento'));
    await tester.pump();

    final estado = _estadoDe(tester);
    expect(estado.seleccionados, hasLength(2));
  });

  testWidgets('al desmarcar el último objetivo vuelve el estado vacío', (
    tester,
  ) async {
    await _montarPerfil(tester);

    await tester.tap(find.text('Distancia semanal'));
    await tester.pump();
    await tester.tap(find.text('Distancia semanal'));
    await tester.pump();

    expect(find.text('Aún no has elegido objetivos'), findsOneWidget);
    expect(_estadoDe(tester).sinObjetivos, isTrue);
  });

  testWidgets('sin objetivos marcados no se puede guardar', (tester) async {
    await _montarPerfil(tester);

    expect(_botonGuardar(tester).onPressed, isNull);
  });

  group('configuración del objetivo de distancia', () {
    testWidgets('el campo aparece al marcar el objetivo, con su valor por '
        'defecto', (tester) async {
      await _montarPerfil(tester);

      expect(find.byType(TextField), findsNothing);

      await _marcarDistancia(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('km por semana'), findsOneWidget);
    });

    testWidgets('conserva el valor escrito al desmarcar y volver a marcar', (
      tester,
    ) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();

      // Desmarcar oculta el campo; volver a marcar debe recuperar el valor.
      await _marcarDistancia(tester);
      expect(find.byType(TextField), findsNothing);

      await _marcarDistancia(tester);
      expect(find.text('25'), findsOneWidget);
      expect(_estadoDe(tester).valorDe(TipoObjetivo.distancia), 25);
    });

    testWidgets('con el campo vacío muestra error y bloquea el guardado', (
      tester,
    ) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Ingresa la distancia'), findsOneWidget);
      expect(_botonGuardar(tester).onPressed, isNull);
    });

    testWidgets('por debajo del mínimo muestra error', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      expect(find.text('El mínimo es 0.1 km por semana'), findsOneWidget);
      expect(_estadoDe(tester).valorDe(TipoObjetivo.distancia), isNull);
    });

    testWidgets('admite una meta de 0.1 km', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '0.1');
      await tester.pump();

      expect(_estadoDe(tester).valorDe(TipoObjetivo.distancia), 0.1);
      expect(_botonGuardar(tester).onPressed, isNotNull);
    });

    testWidgets('acepta decimales', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '7.5');
      await tester.pump();

      expect(_estadoDe(tester).valorDe(TipoObjetivo.distancia), 7.5);
      expect(_botonGuardar(tester).onPressed, isNotNull);
    });

    testWidgets('no impone un tope superior', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '99999');
      await tester.pump();

      expect(_estadoDe(tester).valorDe(TipoObjetivo.distancia), 99999);
      expect(_botonGuardar(tester).onPressed, isNotNull);
    });

    testWidgets('un objetivo desmarcado con valor inválido no bloquea el '
        'guardado de los demás', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);
      await _marcarFrecuencia(tester);

      await tester.enterText(_campoDe(TipoObjetivo.distancia), '');
      await tester.pump();
      expect(_botonGuardar(tester).onPressed, isNull);

      // Al desmarcar la distancia queda solo la frecuencia, que sí es válida.
      await _marcarDistancia(tester);
      expect(_botonGuardar(tester).onPressed, isNotNull);
    });
  });

  group('configuración del objetivo de frecuencia', () {
    testWidgets('el campo aparece al marcar el objetivo, con su valor por '
        'defecto', (tester) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('veces por semana'), findsOneWidget);
    });

    testWidgets('rechaza más de 7 veces por semana', (tester) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      await tester.enterText(find.byType(TextField), '8');
      await tester.pump();

      expect(
        find.text('Debe estar entre 1 y 7 veces por semana'),
        findsOneWidget,
      );
      expect(_estadoDe(tester).valorDe(TipoObjetivo.frecuencia), isNull);
      expect(_botonGuardar(tester).onPressed, isNull);
    });

    testWidgets('acepta los extremos del rango', (tester) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      for (final valor in ['1', '7']) {
        await tester.enterText(find.byType(TextField), valor);
        await tester.pump();

        expect(
          _estadoDe(tester).valorDe(TipoObjetivo.frecuencia),
          int.parse(valor),
        );
      }
    });

    testWidgets('no deja escribir decimales', (tester) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      await tester.enterText(find.byType(TextField), '3.5');
      await tester.pump();

      // El campo rechaza la entrada y conserva el valor anterior.
      expect(find.text('3'), findsOneWidget);
      expect(_estadoDe(tester).valorDe(TipoObjetivo.frecuencia), 3);
    });

    testWidgets('con el campo vacío muestra error y bloquea el guardado', (
      tester,
    ) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Ingresa la frecuencia'), findsOneWidget);
      expect(_botonGuardar(tester).onPressed, isNull);
    });

    testWidgets('conserva el valor escrito al desmarcar y volver a marcar', (
      tester,
    ) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      await tester.enterText(find.byType(TextField), '5');
      await tester.pump();

      await _marcarFrecuencia(tester);
      await _marcarFrecuencia(tester);

      expect(find.text('5'), findsOneWidget);
      expect(_estadoDe(tester).valorDe(TipoObjetivo.frecuencia), 5);
    });
  });

  testWidgets('cada objetivo guarda su propio valor por separado', (
    tester,
  ) async {
    await _montarPerfil(tester);
    await _marcarDistancia(tester);
    await _marcarFrecuencia(tester);

    await tester.enterText(_campoDe(TipoObjetivo.distancia), '12.5');
    await tester.enterText(_campoDe(TipoObjetivo.frecuencia), '4');
    await tester.pump();

    final estado = _estadoDe(tester);
    expect(estado.valorDe(TipoObjetivo.distancia), 12.5);
    expect(estado.valorDe(TipoObjetivo.frecuencia), 4);
    expect(_botonGuardar(tester).onPressed, isNotNull);
  });

  group('guardado de objetivos', () {
    testWidgets('guarda los objetivos marcados y sigue hacia permisos', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso();
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await tester.enterText(_campoDe(TipoObjetivo.distancia), '12.5');
      await tester.pump();

      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(repositorio.guardado, {TipoObjetivo.distancia: 12.5});
      expect(find.text('Objetivos guardados'), findsOneWidget);
      expect(find.byType(PermisosScreen), findsOneWidget);
    });

    testWidgets('guarda los dos objetivos cuando ambos están marcados', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso();
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await _marcarFrecuencia(tester);
      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(repositorio.guardado, {
        TipoObjetivo.distancia: 10,
        TipoObjetivo.frecuencia: 3,
      });
    });

    testWidgets('un objetivo desmarcado no se guarda', (tester) async {
      final repositorio = _RepositorioFalso();
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await _marcarFrecuencia(tester);
      await _marcarDistancia(tester);

      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(repositorio.guardado, {TipoObjetivo.frecuencia: 3});
    });

    testWidgets('sin sesión avisa y se queda en el perfil', (tester) async {
      final repositorio = _RepositorioFalso()
        ..errorAlGuardar = const SesionRequeridaException();
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Inicia sesión para guardar tus objetivos'),
        findsOneWidget,
      );
      expect(find.byType(PermisosScreen), findsNothing);
    });

    testWidgets('si el guardado falla avisa y se queda en el perfil', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso()
        ..errorAlGuardar = Exception('sin conexión');
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudieron guardar tus objetivos'),
        findsOneWidget,
      );
      expect(find.byType(PermisosScreen), findsNothing);
    });

    testWidgets('muestra progreso mientras guarda', (tester) async {
      final repositorio = _RepositorioFalso()..demorar = true;
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await tester.tap(find.text('Guardar y continuar'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_botonGuardar(tester).onPressed, isNull);

      repositorio.completar();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('con un valor inválido no se puede guardar', (tester) async {
      final repositorio = _RepositorioFalso();
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarDistancia(tester);
      await tester.enterText(_campoDe(TipoObjetivo.distancia), '');
      await tester.pump();

      expect(_botonGuardar(tester).onPressed, isNull);
      expect(repositorio.guardado, isNull);
    });
  });

  group('edición de objetivos ya configurados', () {
    testWidgets('precarga los objetivos guardados con sus valores', (
      tester,
    ) async {
      await _montarPerfil(
        tester,
        repositorio: _RepositorioFalso(
          existentes: {TipoObjetivo.distancia: 12.5},
        ),
      );

      final estado = _estadoDe(tester);
      expect(estado.seleccionados, {TipoObjetivo.distancia});
      expect(estado.valorDe(TipoObjetivo.distancia), 12.5);

      // La distancia llega marcada y con su valor; la frecuencia, sin marcar.
      expect(find.text('12.5'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Aún no has elegido objetivos'), findsNothing);
    });

    testWidgets('precarga los dos objetivos cuando ambos estaban guardados', (
      tester,
    ) async {
      await _montarPerfil(
        tester,
        repositorio: _RepositorioFalso(
          existentes: {
            TipoObjetivo.distancia: 20,
            TipoObjetivo.frecuencia: 5,
          },
        ),
      );

      expect(find.text('20'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(_estadoDe(tester).seleccionados, hasLength(2));
    });

    testWidgets('sin nada guardado arranca con el estado vacío', (
      tester,
    ) async {
      await _montarPerfil(tester, repositorio: _RepositorioFalso());

      expect(find.text('Aún no has elegido objetivos'), findsOneWidget);
      expect(_estadoDe(tester).sinObjetivos, isTrue);
    });

    testWidgets('permite modificar un valor precargado y guardarlo', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso(
        existentes: {TipoObjetivo.distancia: 10},
      );
      await _montarPerfil(tester, repositorio: repositorio);

      await tester.enterText(_campoDe(TipoObjetivo.distancia), '20');
      await tester.pump();

      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(repositorio.guardado, {TipoObjetivo.distancia: 20});
    });

    testWidgets('permite desmarcar un objetivo precargado', (tester) async {
      final repositorio = _RepositorioFalso(
        existentes: {TipoObjetivo.distancia: 10, TipoObjetivo.frecuencia: 5},
      );
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarFrecuencia(tester);

      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(repositorio.guardado, {TipoObjetivo.distancia: 10});
    });

    testWidgets('permite marcar un objetivo que no estaba guardado', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso(
        existentes: {TipoObjetivo.distancia: 10},
      );
      await _montarPerfil(tester, repositorio: repositorio);

      await _marcarFrecuencia(tester);

      await tester.tap(find.text('Guardar y continuar'));
      await tester.pumpAndSettle();

      expect(repositorio.guardado, {
        TipoObjetivo.distancia: 10,
        TipoObjetivo.frecuencia: 3,
      });
    });

    testWidgets('sin sesión muestra los valores por defecto, no un error', (
      tester,
    ) async {
      await _montarPerfil(
        tester,
        repositorio: _RepositorioFalso()
          ..errorAlCargar = const SesionRequeridaException(),
      );

      expect(find.text('No pudimos cargar tus objetivos'), findsNothing);
      expect(find.text('Distancia semanal'), findsOneWidget);
      expect(_estadoDe(tester).carga, EstadoCarga.listo);
    });

    testWidgets('si la carga falla bloquea la edición y ofrece reintentar', (
      tester,
    ) async {
      final repositorio = _RepositorioFalso(
        existentes: {TipoObjetivo.distancia: 10},
      )..errorAlCargar = Exception('sin conexión');
      await _montarPerfil(tester, repositorio: repositorio);

      expect(find.text('No pudimos cargar tus objetivos'), findsOneWidget);
      // Nada de editar ni guardar mientras no sepamos qué había.
      expect(find.text('Distancia semanal'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      repositorio.errorAlCargar = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar tus objetivos'), findsNothing);
      expect(find.text('10'), findsOneWidget);
      expect(_botonGuardar(tester).onPressed, isNotNull);
    });
  });
}

/// Repositorio de mentira: devuelve los objetivos que se le configuren,
/// recuerda lo último que se le pidió guardar y puede fingir fallos o esperas.
class _RepositorioFalso implements ObjetivosRepository {
  _RepositorioFalso({this.existentes = const {}});

  /// Lo que el usuario ya tenía guardado.
  Map<TipoObjetivo, num> existentes;

  /// Lo último que se le pidió guardar.
  Map<TipoObjetivo, num>? guardado;

  Object? errorAlCargar;
  Object? errorAlGuardar;
  bool demorar = false;

  final _espera = Completer<void>();

  void completar() => _espera.complete();

  @override
  Future<Map<TipoObjetivo, num>> cargar() async {
    if (errorAlCargar case final error?) throw error;
    return existentes;
  }

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {
    if (demorar) await _espera.future;
    if (errorAlGuardar case final error?) throw error;
    guardado = objetivos;
  }
}

Future<void> _marcarDistancia(WidgetTester tester) async {
  await tester.tap(find.text('Distancia semanal'));
  await tester.pump();
}

Future<void> _marcarFrecuencia(WidgetTester tester) async {
  await tester.tap(find.text('Frecuencia de entrenamiento'));
  await tester.pump();
}

/// El campo de un objetivo concreto, para cuando hay varios en pantalla.
Finder _campoDe(TipoObjetivo tipo) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is ConfiguracionValorObjetivo && widget.tipo == tipo,
  ),
  matching: find.byType(TextField),
);

FilledButton _botonGuardar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

Future<void> _montarPerfil(
  WidgetTester tester, {
  ObjetivosRepository? repositorio,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/perfil',
    routes: [
      GoRoute(path: '/perfil', builder: (_, _) => const PerfilScreen()),
      GoRoute(path: '/permisos', builder: (_, _) => const PermisosScreen()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        objetivosRepositoryProvider.overrideWithValue(
          repositorio ?? _RepositorioFalso(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Estado actual del perfil, leído del [ProviderScope] que monta la pantalla.
PerfilState _estadoDe(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(PerfilScreen)),
).read(perfilProvider);
