import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/auth/login_screen.dart';

void main() {
  Future<void> abrirPantalla(WidgetTester tester) async {
    // Tamaño de un celular: 390 x 844 puntos.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
  }

  Future<void> tocarIniciarSesion(WidgetTester tester) async {
    // Se busca dentro del botón: el título dice "Inicia sesión", muy parecido.
    final boton = find.widgetWithText(FilledButton, 'Iniciar sesión');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  group('Criterio 4 — campos vacíos', () {
    testWidgets('marca los dos campos si están vacíos', (tester) async {
      await abrirPantalla(tester);

      await tocarIniciarSesion(tester);

      expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
      expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    });

    testWidgets('marca solo la contraseña si el correo está lleno', (
      tester,
    ) async {
      await abrirPantalla(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'ana@correo.com',
      );
      await tocarIniciarSesion(tester);

      expect(find.text('Ingresa tu correo electrónico'), findsNothing);
      expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    });
  });
}
