import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/revision_ruta.dart';
import 'package:traza/widgets/dialogo_motivo_rechazo.dart';

/// El motivo es obligatorio para rechazar una ruta (SCRUM-330, criterio 6 de
/// SCRUM-321).
void main() {
  /// Abre el diálogo. La lista que devuelve recibe lo que el diálogo
  /// devolvió al cerrarse.
  Future<List<String?>> abrir(WidgetTester tester) async {
    final resultados = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => resultados.add(
                await pedirMotivoRechazo(context, titulo: 'Rechazar ruta'),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultados;
  }

  Future<void> confirmar(WidgetTester tester) async {
    await tester.tap(find.byKey(DialogoMotivoRechazo.claveConfirmar));
    await tester.pumpAndSettle();
  }

  testWidgets('sin motivo no deja rechazar y dice que es obligatorio', (
    tester,
  ) async {
    final resultados = await abrir(tester);

    await confirmar(tester);

    expect(find.text('El motivo es obligatorio.'), findsOneWidget);
    expect(find.byType(DialogoMotivoRechazo), findsOneWidget);
    expect(resultados, isEmpty);
  });

  testWidgets('un motivo de solo espacios tampoco cuenta', (tester) async {
    final resultados = await abrir(tester);

    await tester.enterText(find.byKey(DialogoMotivoRechazo.claveMotivo), '   ');
    await confirmar(tester);

    expect(find.text('El motivo es obligatorio.'), findsOneWidget);
    expect(resultados, isEmpty);
  });

  testWidgets('un motivo demasiado largo se señala sin cortarlo', (
    tester,
  ) async {
    final resultados = await abrir(tester);
    final largo = 'a' * (maxCaracteresMotivoRechazo + 5);

    await tester.enterText(find.byKey(DialogoMotivoRechazo.claveMotivo), largo);
    await confirmar(tester);

    expect(find.textContaining('300'), findsWidgets);
    expect(resultados, isEmpty);
    final campo = tester.widget<TextField>(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
    );
    expect(campo.controller!.text, largo);
  });

  testWidgets('el error se va en cuanto se escribe', (tester) async {
    await abrir(tester);
    await confirmar(tester);

    await tester.enterText(find.byKey(DialogoMotivoRechazo.claveMotivo), 'C');
    await tester.pump();

    expect(find.text('El motivo es obligatorio.'), findsNothing);
  });

  testWidgets('con motivo lo devuelve sin espacios en los extremos', (
    tester,
  ) async {
    final resultados = await abrir(tester);

    await tester.enterText(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
      '  Cruza una autopista  ',
    );
    await confirmar(tester);

    expect(find.byType(DialogoMotivoRechazo), findsNothing);
    expect(resultados, ['Cruza una autopista']);
  });

  testWidgets('cancelar no rechaza', (tester) async {
    final resultados = await abrir(tester);

    await tester.enterText(
      find.byKey(DialogoMotivoRechazo.claveMotivo),
      'Lo pense mejor',
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(resultados, [null]);
  });
}
