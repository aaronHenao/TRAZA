import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recompensa.dart';
import 'package:traza/widgets/tarjeta_recompensa.dart';

import '../utiles/recompensas_repository_falso.dart';

/// Pruebas de la tarjeta con la que se pinta una recompensa en el catálogo
/// del corredor y en la gestión del administrador (SCRUM-374).
void main() {
  Future<void> montar(
    WidgetTester tester,
    Recompensa recompensa, {
    bool conDisponibilidad = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TarjetaRecompensa(
            recompensa: recompensa,
            conDisponibilidad: conDisponibilidad,
          ),
        ),
      ),
    );
  }

  group('texto de los puntos', () {
    test('un punto va en singular', () {
      expect(TarjetaRecompensa.textoPuntos(1), '1 punto');
    });

    test('desde dos, en plural', () {
      expect(TarjetaRecompensa.textoPuntos(2), '2 puntos');
      expect(TarjetaRecompensa.textoPuntos(150), '150 puntos');
    });

    test('sin separador de miles', () {
      expect(TarjetaRecompensa.textoPuntos(1500), '1500 puntos');
    });
  });

  testWidgets('muestra el nombre, la descripción y los puntos que cuesta '
      '(criterio 3 de SCRUM-374)', (tester) async {
    await montar(tester, recompensaDePrueba());

    expect(find.text('Vale de hidratación'), findsOneWidget);
    expect(
      find.text('Una bebida isotónica en la tienda aliada.'),
      findsOneWidget,
    );
    expect(find.text('150 puntos'), findsOneWidget);
  });

  testWidgets('sin pedirlo no dice si está disponible: el corredor solo ve '
      'lo que puede obtener', (tester) async {
    await montar(tester, recompensaDePrueba());

    expect(find.text('Disponible'), findsNothing);
    expect(find.text('No disponible'), findsNothing);
  });

  testWidgets('en la gestión dice que está disponible', (tester) async {
    await montar(tester, recompensaDePrueba(), conDisponibilidad: true);

    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('No disponible'), findsNothing);
  });

  testWidgets('en la gestión dice que no está disponible', (tester) async {
    await montar(
      tester,
      recompensaDePrueba(disponible: false),
      conDisponibilidad: true,
    );

    expect(find.text('No disponible'), findsOneWidget);
    expect(find.text('Disponible'), findsNothing);
    // Los puntos se ven igual: el administrador los necesita para decidir.
    expect(find.text('150 puntos'), findsOneWidget);
  });

  test('cada recompensa tiene su clave a partir del id', () {
    expect(TarjetaRecompensa.claveDe('abc'), const Key('recompensa-abc'));
  });

  group('acciones al pie (SCRUM-380)', () {
    Future<void> montarConAcciones(
      WidgetTester tester,
      List<Widget> acciones,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TarjetaRecompensa(
              recompensa: recompensaDePrueba(),
              conDisponibilidad: true,
              acciones: acciones,
            ),
          ),
        ),
      );
    }

    final botones = find.byWidgetPredicate((w) => w is ButtonStyleButton);

    testWidgets('sin acciones no pinta ningún botón: así la ve el corredor', (
      tester,
    ) async {
      await montar(tester, recompensaDePrueba());

      expect(botones, findsNothing);
    });

    testWidgets('con una lista de acciones vacía tampoco', (tester) async {
      await montarConAcciones(tester, const []);

      expect(botones, findsNothing);
    });

    testWidgets('con acciones las pinta dentro de la tarjeta, debajo de los '
        'puntos, y responden al toque', (tester) async {
      var tocada = false;
      await montarConAcciones(tester, [
        TextButton(
          key: const Key('accion-de-prueba'),
          onPressed: () => tocada = true,
          child: const Text('Cambiar puntos'),
        ),
      ]);

      final accion = find.byKey(const Key('accion-de-prueba'));
      expect(
        find.descendant(of: find.byType(TarjetaRecompensa), matching: accion),
        findsOneWidget,
      );
      expect(find.text('Cambiar puntos'), findsOneWidget);
      // Al pie: debajo de los puntos y de la disponibilidad.
      expect(
        tester.getTopLeft(accion).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('150 puntos')).dy),
      );
      expect(
        tester.getTopLeft(accion).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Disponible')).dy),
      );
      // Lo demás de la tarjeta sigue ahí.
      expect(find.text('Vale de hidratación'), findsOneWidget);

      await tester.tap(accion);
      expect(tocada, isTrue);
    });

    testWidgets('varias acciones van en una misma fila', (tester) async {
      await montarConAcciones(tester, [
        TextButton(
          key: const Key('primera'),
          onPressed: () {},
          child: const Text('Cambiar puntos'),
        ),
        TextButton(
          key: const Key('segunda'),
          onPressed: () {},
          child: const Text('Retirar'),
        ),
      ]);

      final primera = find.byKey(const Key('primera'));
      final segunda = find.byKey(const Key('segunda'));
      expect(primera, findsOneWidget);
      expect(segunda, findsOneWidget);
      expect(tester.getCenter(primera).dy, tester.getCenter(segunda).dy);
      expect(tester.getCenter(primera).dx, isNot(tester.getCenter(segunda).dx));
    });
  });
}
