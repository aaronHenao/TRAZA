import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/screens/onboarding/permisos_screen.dart';

/// Pruebas de la pantalla de permisos (SCRUM-76).
void main() {
  Future<void> montar(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/permisos',
      routes: [
        GoRoute(
          path: '/permisos',
          builder: (context, state) => const PermisosScreen(),
        ),
        GoRoute(
          path: '/inicio',
          builder: (context, state) =>
              const Scaffold(body: Text('Pantalla Inicio')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('explica para qué se usa cada permiso', (tester) async {
    await montar(tester);

    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.textContaining('trazar tu recorrido'), findsOneWidget);
    expect(find.text('Permitir ubicación'), findsOneWidget);

    expect(find.text('Datos de salud'), findsOneWidget);
    expect(find.textContaining('métricas de salud'), findsOneWidget);
    expect(find.text('Permitir acceso'), findsOneWidget);
  });

  testWidgets('"Ahora no" avisa que se puede activar después', (tester) async {
    await montar(tester);

    await tester.tap(find.text('Ahora no').first);
    await tester.pump();

    expect(
      find.text('Podrás activarlo luego cuando lo necesites'),
      findsOneWidget,
    );
    // Deja que el aviso termine su temporizador.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('"Continuar" lleva a Inicio', (tester) async {
    await montar(tester);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla Inicio'), findsOneWidget);
  });
}
