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
}
