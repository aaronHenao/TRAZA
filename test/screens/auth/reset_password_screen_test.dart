import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/screens/auth/login_screen.dart';
import 'package:traza/screens/auth/reset_password_screen.dart';
import 'package:traza/services/auth_service.dart';

import '../../utils/app_de_prueba.dart';

/// Service falso: la pantalla cree que habla con Supabase, pero no hay red.
class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.cerrarSesion()).thenAnswer((_) async {});
  });

  Future<void> montar(WidgetTester tester, String ruta) async {
    // Tamaño de un celular: 390 x 844 puntos.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      appDePrueba(auth: auth, ruta: ruta, extra: 'ana@correo.com'),
    );
  }

  Future<void> tocar(WidgetTester tester, String textoBoton) async {
    final boton = find.widgetWithText(FilledButton, textoBoton);
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  Future<void> llenar(
    WidgetTester tester, {
    String codigo = '123456',
    String password = 'Nueva123!',
    String confirmacion = 'Nueva123!',
  }) async {
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), codigo);
    await tester.enterText(campos.at(1), password);
    await tester.enterText(campos.at(2), confirmacion);
  }

  void verificarQueNoLlamoAlService() {
    verifyNever(
      () => auth.verificarCodigoRecuperacion(
        correo: any(named: 'correo'),
        codigo: any(named: 'codigo'),
      ),
    );
  }

  group('Paso 1 — pedir el código (SCRUM-73)', () {
    testWidgets('al cerrar el mensaje abre la pantalla del código', (
      tester,
    ) async {
      when(
        () => auth.solicitarRecuperacion(correo: any(named: 'correo')),
      ).thenAnswer((_) async {});
      await montar(tester, '/recuperar');

      await tocar(tester, 'Enviar código');
      expect(find.text('Revisa tu correo'), findsOneWidget);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
    });
  });

  group('Paso 2 — código y nueva contraseña (SCRUM-74)', () {
    testWidgets('el código solo acepta 6 dígitos', (tester) async {
      await montar(tester, '/restablecer');

      final campoCodigo = find.byType(TextFormField).first;
      await tester.enterText(campoCodigo, 'ab12345678');

      // Se lee el controller: find.text también encontraría el hint "123456".
      final campo = tester.widget<TextFormField>(campoCodigo);
      expect(campo.controller!.text, '123456');
    });

    testWidgets('criterio 5: contraseñas diferentes', (tester) async {
      await montar(tester, '/restablecer');

      await llenar(tester, confirmacion: 'Otra123!');
      await tocar(tester, 'Cambiar contraseña');

      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
      verificarQueNoLlamoAlService();
    });

    testWidgets('criterio 4: actualiza la contraseña', (tester) async {
      when(
        () => auth.verificarCodigoRecuperacion(
          correo: any(named: 'correo'),
          codigo: any(named: 'codigo'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => auth.cambiarPassword(nuevaPassword: any(named: 'nuevaPassword')),
      ).thenAnswer((_) async {});
      await montar(tester, '/restablecer');

      await llenar(tester);
      await tocar(tester, 'Cambiar contraseña');

      verify(
        () => auth.verificarCodigoRecuperacion(
          correo: 'ana@correo.com',
          codigo: '123456',
        ),
      ).called(1);
      verify(() => auth.cambiarPassword(nuevaPassword: 'Nueva123!')).called(1);
      expect(find.text('Contraseña actualizada'), findsOneWidget);
    });

    testWidgets('SCRUM-75: al cerrar el mensaje deja solo el login', (
      tester,
    ) async {
      when(
        () => auth.verificarCodigoRecuperacion(
          correo: any(named: 'correo'),
          codigo: any(named: 'codigo'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => auth.cambiarPassword(nuevaPassword: any(named: 'nuevaPassword')),
      ).thenAnswer((_) async {});
      await montar(tester, '/restablecer');

      await llenar(tester);
      await tocar(tester, 'Cambiar contraseña');
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      // Nada debajo del login: "atrás" no vuelve al formulario del código.
      final navegador = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navegador.canPop(), isFalse);
    });

    testWidgets('muestra el error que manda el service', (tester) async {
      when(
        () => auth.verificarCodigoRecuperacion(
          correo: any(named: 'correo'),
          codigo: any(named: 'codigo'),
        ),
      ).thenThrow(
        const RecuperacionException(
          titulo: 'Código no válido',
          mensaje: 'El código es incorrecto o ya venció. Pide uno nuevo.',
        ),
      );
      await montar(tester, '/restablecer');

      await llenar(tester);
      await tocar(tester, 'Cambiar contraseña');

      expect(find.text('Código no válido'), findsOneWidget);
    });
  });
}
