import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:traza/core/router/rutas.dart';
import 'package:traza/features/perfil/domain/tipo_objetivo.dart';
import 'package:traza/features/perfil/presentation/perfil_controller.dart';
import 'package:traza/features/perfil/presentation/perfil_screen.dart';
import 'package:traza/features/perfil/presentation/widgets/configuracion_valor_objetivo.dart';
import 'package:traza/features/permisos/presentation/permisos_screen.dart';

/// Pruebas de la interfaz de perfil (SCRUM-86). La cobertura completa de la
/// gestión de objetivos llega en SCRUM-128.
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

    final controlador = _controladorDe(tester);
    expect(controlador.seleccionados, hasLength(2));
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
    expect(_controladorDe(tester).sinObjetivos, isTrue);
  });

  testWidgets('el botón Continuar navega a la pantalla de permisos', (
    tester,
  ) async {
    await _montarPerfil(tester);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.byType(PermisosScreen), findsOneWidget);
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
      expect(_controladorDe(tester).valorDe(TipoObjetivo.distancia), 25);
    });

    testWidgets('con el campo vacío muestra error y bloquea Continuar', (
      tester,
    ) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Ingresa la distancia'), findsOneWidget);
      expect(_botonContinuar(tester).onPressed, isNull);
    });

    testWidgets('por debajo del mínimo muestra error', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      expect(find.text('El mínimo es 0.1 km por semana'), findsOneWidget);
      expect(_controladorDe(tester).valorDe(TipoObjetivo.distancia), isNull);
    });

    testWidgets('admite una meta de 0.1 km', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '0.1');
      await tester.pump();

      expect(_controladorDe(tester).valorDe(TipoObjetivo.distancia), 0.1);
      expect(_botonContinuar(tester).onPressed, isNotNull);
    });

    testWidgets('acepta decimales', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '7.5');
      await tester.pump();

      expect(_controladorDe(tester).valorDe(TipoObjetivo.distancia), 7.5);
      expect(_botonContinuar(tester).onPressed, isNotNull);
    });

    testWidgets('no impone un tope superior', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '99999');
      await tester.pump();

      expect(_controladorDe(tester).valorDe(TipoObjetivo.distancia), 99999);
      expect(_botonContinuar(tester).onPressed, isNotNull);
    });

    testWidgets('un objetivo desmarcado con valor inválido no bloquea '
        'Continuar', (tester) async {
      await _montarPerfil(tester);
      await _marcarDistancia(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(_botonContinuar(tester).onPressed, isNull);

      await _marcarDistancia(tester);
      expect(_botonContinuar(tester).onPressed, isNotNull);
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
      expect(_controladorDe(tester).valorDe(TipoObjetivo.frecuencia), isNull);
      expect(_botonContinuar(tester).onPressed, isNull);
    });

    testWidgets('acepta los extremos del rango', (tester) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      for (final valor in ['1', '7']) {
        await tester.enterText(find.byType(TextField), valor);
        await tester.pump();

        expect(
          _controladorDe(tester).valorDe(TipoObjetivo.frecuencia),
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
      expect(_controladorDe(tester).valorDe(TipoObjetivo.frecuencia), 3);
    });

    testWidgets('con el campo vacío muestra error y bloquea Continuar', (
      tester,
    ) async {
      await _montarPerfil(tester);
      await _marcarFrecuencia(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Ingresa la frecuencia'), findsOneWidget);
      expect(_botonContinuar(tester).onPressed, isNull);
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
      expect(_controladorDe(tester).valorDe(TipoObjetivo.frecuencia), 5);
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

    final controlador = _controladorDe(tester);
    expect(controlador.valorDe(TipoObjetivo.distancia), 12.5);
    expect(controlador.valorDe(TipoObjetivo.frecuencia), 4);
    expect(_botonContinuar(tester).onPressed, isNotNull);
  });
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

FilledButton _botonContinuar(WidgetTester tester) =>
    tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continuar'),
    );

Future<void> _montarPerfil(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: Rutas.perfil,
    routes: [
      GoRoute(path: Rutas.perfil, builder: (_, _) => const PerfilScreen()),
      GoRoute(path: Rutas.permisos, builder: (_, _) => const PermisosScreen()),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => PerfilController(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

PerfilController _controladorDe(WidgetTester tester) =>
    Provider.of<PerfilController>(
      tester.element(find.byType(PerfilScreen)),
      listen: false,
    );
