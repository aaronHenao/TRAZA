import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/progresion.dart';
import 'package:traza/widgets/barra_progresion.dart';

/// Pruebas del indicador visual de avance (SCRUM-188).
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const niveles = [bronce, plata];

  Future<void> montar(WidgetTester tester, int experiencia) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarraProgresion(
            progresion: Progresion.calcular(
              experiencia: experiencia,
              niveles: niveles,
            ),
          ),
        ),
      ),
    );
  }

  double? valorDeLaBarra(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byKey(BarraProgresion.clave))
      .value;

  testWidgets('llena la barra en proporción a lo recorrido del tramo', (
    tester,
  ) async {
    // De Bronce (100) a Plata (500) hay 400; con 200 lleva 100 recorridos.
    await montar(tester, 200);

    expect(valorDeLaBarra(tester), closeTo(0.25, 0.0001));
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('100 de 400 XP'), findsOneWidget);
  });

  testWidgets('recién alcanzado un nivel, la barra arranca vacía', (
    tester,
  ) async {
    await montar(tester, 100);

    expect(valorDeLaBarra(tester), 0);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('a un punto del siguiente nivel está casi llena', (tester) async {
    await montar(tester, 499);

    expect(valorDeLaBarra(tester), closeTo(0.9975, 0.0001));
    // 100% diría que ya llegó, y todavía le falta un punto.
    expect(find.text('99%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('antes del primer nivel el tramo se cuenta desde cero', (
    tester,
  ) async {
    await montar(tester, 40);

    expect(valorDeLaBarra(tester), closeTo(0.4, 0.0001));
    // El tramo va de cero al primer umbral.
    expect(find.text('40 de 100 XP'), findsOneWidget);
  });

  testWidgets('en el nivel más alto no se dibuja: no hay meta que mostrar', (
    tester,
  ) async {
    await montar(tester, 900);

    expect(find.byKey(BarraProgresion.clave), findsNothing);
  });

  testWidgets('sin niveles configurados tampoco se dibuja', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarraProgresion(
            progresion: Progresion.calcular(
              experiencia: 300,
              niveles: const [],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(BarraProgresion.clave), findsNothing);
  });

  testWidgets('la barra se describe para quien usa lector de pantalla', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await montar(tester, 200);

    expect(
      find.bySemanticsLabel(
        'Llevas 100 de 400 puntos de experiencia hacia '
        'Plata',
      ),
      findsOneWidget,
    );
    semantica.dispose();
  });
}
