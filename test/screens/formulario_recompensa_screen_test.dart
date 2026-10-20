import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/screens/admin/formulario_recompensa_screen.dart';
import 'package:traza/screens/admin/gestion_recompensas_screen.dart';
import 'package:traza/services/recompensas_provider.dart';
import 'package:traza/services/recompensas_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas del formulario con el que el administrador crea una recompensa
/// (SCRUM-374): lo que se registra y cómo señala lo que hay que corregir.
void main() {
  late RecompensasRepositorioFalso repositorio;

  /// Abre el formulario desde una gestión de mentira, para tener a dónde
  /// volver al guardar.
  Future<void> abrirFormulario(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = RecompensasRepositorioFalso();
    final router = GoRouter(
      initialLocation: GestionRecompensasScreen.ruta,
      routes: [
        GoRoute(
          path: GestionRecompensasScreen.ruta,
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(GestionRecompensasScreen.rutaNueva),
              child: const Text('Gestión'),
            ),
          ),
        ),
        GoRoute(
          path: GestionRecompensasScreen.rutaNueva,
          builder: (_, _) => const FormularioRecompensaScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recompensasRepositoryProvider.overrideWithValue(repositorio),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Gestión'));
    await tester.pumpAndSettle();
  }

  Future<void> llenar(
    WidgetTester tester, {
    String nombre = 'Vale de hidratación',
    String descripcion = 'Una bebida isotónica en la tienda aliada.',
    String puntos = '150',
  }) async {
    await tester.enterText(
      find.byKey(FormularioRecompensaScreen.claveNombre),
      nombre,
    );
    await tester.enterText(
      find.byKey(FormularioRecompensaScreen.claveDescripcion),
      descripcion,
    );
    await tester.enterText(
      find.byKey(FormularioRecompensaScreen.clavePuntos),
      puntos,
    );
    await tester.pump();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.byKey(FormularioRecompensaScreen.claveGuardar));
    await tester.pumpAndSettle();
  }

  /// Lo que dice el campo de texto con [clave].
  String textoDe(WidgetTester tester, Key clave) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(clave),
          matching: find.byType(EditableText),
          matchRoot: true,
        ),
      )
      .controller
      .text;

  /// Si el interruptor de disponibilidad está encendido.
  bool disponibleEncendido(WidgetTester tester) => tester
      .widget<Switch>(
        find.descendant(
          of: find.byKey(FormularioRecompensaScreen.claveDisponible),
          matching: find.byType(Switch),
          matchRoot: true,
        ),
      )
      .value;

  /// El campo que queda justo encima de [texto]: así se comprueba que cada
  /// error se pinta bajo su propio campo y no en un aviso general.
  ///
  /// Null si el texto queda por encima de todos los campos, como pasaría con
  /// un aviso general en la cabecera.
  Key? campoSobre(WidgetTester tester, String texto) {
    final altura = tester.getCenter(find.text(texto)).dy;
    Key? masCercano;
    var alturaMasCercano = double.negativeInfinity;
    for (final clave in [
      FormularioRecompensaScreen.claveNombre,
      FormularioRecompensaScreen.claveDescripcion,
      FormularioRecompensaScreen.clavePuntos,
    ]) {
      final arriba = tester.getTopLeft(find.byKey(clave)).dy;
      if (arriba < altura && arriba > alturaMasCercano) {
        masCercano = clave;
        alturaMasCercano = arriba;
      }
    }
    return masCercano;
  }

  group('registrar (criterio 1 de SCRUM-374)', () {
    testWidgets(
      'se presenta como una recompensa nueva, disponible de entrada',
      (tester) async {
        await abrirFormulario(tester);

        expect(find.text('Nueva recompensa'), findsOneWidget);
        expect(disponibleEncendido(tester), isTrue);
      },
    );

    testWidgets('con los cuatro datos registra la recompensa y vuelve con un '
        'aviso', (tester) async {
      await abrirFormulario(tester);
      await llenar(tester, nombre: '  Vale de hidratación  ');

      await guardar(tester);

      final recibida = repositorio.recibida!;
      expect(recibida.nombre, 'Vale de hidratación');
      expect(recibida.descripcion, 'Una bebida isotónica en la tienda aliada.');
      expect(recibida.puntosRequeridos, 150);
      expect(recibida.disponible, isTrue);
      // De vuelta en la gestión, con el aviso de que quedó creada.
      expect(find.text('Gestión'), findsOneWidget);
      expect(find.byType(FormularioRecompensaScreen), findsNothing);
      expect(find.text('Recompensa creada'), findsOneWidget);
    });

    testWidgets('con la disponibilidad apagada se registra como no '
        'disponible', (tester) async {
      await abrirFormulario(tester);
      await llenar(tester);
      await tester.tap(find.byKey(FormularioRecompensaScreen.claveDisponible));
      await tester.pump();
      expect(disponibleEncendido(tester), isFalse);

      await guardar(tester);

      expect(repositorio.recibida!.disponible, isFalse);
      expect(find.text('Gestión'), findsOneWidget);
    });
  });

  group('campos por corregir (criterio 2 de SCRUM-374)', () {
    testWidgets('antes del primer intento no hay nada en rojo', (tester) async {
      await abrirFormulario(tester);

      expect(find.text('Ponle un nombre a la recompensa.'), findsNothing);
      expect(find.text('Describe en qué consiste.'), findsNothing);
      expect(find.text('Indica cuántos puntos cuesta.'), findsNothing);
    });

    testWidgets('con todo vacío marca los tres campos, cada uno bajo el suyo, '
        'y no registra nada', (tester) async {
      await abrirFormulario(tester);

      await guardar(tester);

      expect(find.text('Ponle un nombre a la recompensa.'), findsOneWidget);
      expect(find.text('Describe en qué consiste.'), findsOneWidget);
      expect(find.text('Indica cuántos puntos cuesta.'), findsOneWidget);
      expect(
        campoSobre(tester, 'Ponle un nombre a la recompensa.'),
        FormularioRecompensaScreen.claveNombre,
      );
      expect(
        campoSobre(tester, 'Describe en qué consiste.'),
        FormularioRecompensaScreen.claveDescripcion,
      );
      expect(
        campoSobre(tester, 'Indica cuántos puntos cuesta.'),
        FormularioRecompensaScreen.clavePuntos,
      );
      expect(find.text('Revisa los campos marcados'), findsOneWidget);
      // Lo importante: no se intentó guardar y sigue en el formulario.
      expect(repositorio.recibida, isNull);
      expect(find.byType(FormularioRecompensaScreen), findsOneWidget);
    });

    testWidgets('con cero puntos marca solo los puntos y no registra', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await llenar(tester, puntos: '0');

      await guardar(tester);

      expect(
        find.text('Los puntos deben ser mayores que cero.'),
        findsOneWidget,
      );
      expect(
        campoSobre(tester, 'Los puntos deben ser mayores que cero.'),
        FormularioRecompensaScreen.clavePuntos,
      );
      expect(find.text('Ponle un nombre a la recompensa.'), findsNothing);
      expect(find.text('Describe en qué consiste.'), findsNothing);
      expect(repositorio.recibida, isNull);
      expect(find.byType(FormularioRecompensaScreen), findsOneWidget);
    });

    testWidgets('con puntos negativos marca solo los puntos y no registra', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await llenar(tester, puntos: '-3');

      await guardar(tester);

      expect(
        find.text('Los puntos deben ser mayores que cero.'),
        findsOneWidget,
      );
      expect(find.text('Ponle un nombre a la recompensa.'), findsNothing);
      expect(repositorio.recibida, isNull);
      expect(find.byType(FormularioRecompensaScreen), findsOneWidget);
    });

    testWidgets('al corregir un campo se le quita su error y los demás siguen '
        'marcados', (tester) async {
      await abrirFormulario(tester);
      await guardar(tester);

      await tester.enterText(
        find.byKey(FormularioRecompensaScreen.claveNombre),
        'Vale de hidratación',
      );
      await tester.pump();

      expect(find.text('Ponle un nombre a la recompensa.'), findsNothing);
      expect(find.text('Describe en qué consiste.'), findsOneWidget);
      expect(find.text('Indica cuántos puntos cuesta.'), findsOneWidget);

      await tester.enterText(
        find.byKey(FormularioRecompensaScreen.clavePuntos),
        '150',
      );
      await tester.pump();

      expect(find.text('Indica cuántos puntos cuesta.'), findsNothing);
      expect(find.text('Describe en qué consiste.'), findsOneWidget);
    });
  });

  group('el guardado falla', () {
    testWidgets('si falla la red avisa y conserva lo escrito', (tester) async {
      await abrirFormulario(tester);
      await llenar(tester);
      repositorio.error = Exception('sin conexión');

      await guardar(tester);

      expect(find.text(CreacionRecompensa.noSePudo), findsOneWidget);
      expect(find.byType(FormularioRecompensaScreen), findsOneWidget);
      expect(
        textoDe(tester, FormularioRecompensaScreen.claveNombre),
        'Vale de hidratación',
      );
      expect(
        textoDe(tester, FormularioRecompensaScreen.claveDescripcion),
        'Una bebida isotónica en la tienda aliada.',
      );
      expect(textoDe(tester, FormularioRecompensaScreen.clavePuntos), '150');
    });

    testWidgets('si la cuenta no es administradora lo dice y no se sale', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await llenar(tester);
      repositorio.error = const SoloAdministradorException();

      await guardar(tester);

      expect(find.text(CreacionRecompensa.soloAdministrador), findsOneWidget);
      expect(find.byType(FormularioRecompensaScreen), findsOneWidget);
      expect(find.text('Gestión'), findsNothing);
    });
  });
}
