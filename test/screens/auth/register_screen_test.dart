import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/screens/auth/login_screen.dart';
import 'package:traza/screens/auth/register_screen.dart';
import 'package:traza/services/auth_service.dart';

/// Service falso: la pantalla cree que habla con Supabase, pero no hay red.
class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAuthService auth;

  setUp(() => auth = _MockAuthService());

  When<Future<bool>> cuandoRegistrar() {
    return when(
      () => auth.registrar(
        nombre: any(named: 'nombre'),
        correo: any(named: 'correo'),
        password: any(named: 'password'),
      ),
    );
  }

  void verificarQueNoLlamoAlService() {
    verifyNever(
      () => auth.registrar(
        nombre: any(named: 'nombre'),
        correo: any(named: 'correo'),
        password: any(named: 'password'),
      ),
    );
  }

  Future<void> abrirPantalla(WidgetTester tester) async {
    // Tamaño de un celular: 390 x 844 puntos.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: RegisterScreen(authService: auth)),
    );
  }

  Future<void> llenarFormulario(
    WidgetTester tester, {
    String nombre = 'Ana',
    String correo = 'ana@correo.com',
    String password = 'Abcdefg1!',
  }) async {
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), nombre);
    await tester.enterText(campos.at(1), correo);
    await tester.enterText(campos.at(2), password);
  }

  Future<void> tocarCrearCuenta(WidgetTester tester) async {
    final boton = find.text('Crear cuenta');
    await tester.ensureVisible(boton);
    await tester.pump();
    await tester.tap(boton);

    // No se usa pumpAndSettle: tras un registro exitoso el spinner del botón
    // sigue girando detrás de la alerta y nunca "se asienta".
    await tester.pump(); // _cargando = true
    await tester.pump(); // responde el service
    await tester.pump(const Duration(milliseconds: 300)); // anima la alerta
  }

  group('Criterio 1 — registro exitoso', () {
    testWidgets('muestra la alerta y redirige al login al cerrarla', (
      tester,
    ) async {
      cuandoRegistrar().thenAnswer((_) async => true);
      await abrirPantalla(tester);

      await llenarFormulario(tester, correo: '  ana@correo.com  ');
      await tocarCrearCuenta(tester);

      expect(find.text('Cuenta creada'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      await tester.tap(find.text('Entendido'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('envía el correo sin espacios y la contraseña intacta', (
      tester,
    ) async {
      cuandoRegistrar().thenAnswer((_) async => true);
      await abrirPantalla(tester);

      await llenarFormulario(tester, correo: '  ana@correo.com  ');
      await tocarCrearCuenta(tester);

      verify(
        () => auth.registrar(
          nombre: 'Ana',
          correo: 'ana@correo.com',
          password: 'Abcdefg1!',
        ),
      ).called(1);
    });
  });

  group('Criterio 2 — correo ya registrado', () {
    testWidgets('muestra la alerta con el mensaje del criterio', (
      tester,
    ) async {
      cuandoRegistrar().thenThrow(CorreoYaRegistradoException());
      await abrirPantalla(tester);

      await llenarFormulario(tester);
      await tocarCrearCuenta(tester);

      expect(find.text('Correo en uso'), findsOneWidget);
      expect(
        find.text('El correo ingresado ya está asociado a una cuenta'),
        findsOneWidget,
      );
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  group('Criterio 3 — correo inválido', () {
    testWidgets('marca el campo y no llama al service', (tester) async {
      await abrirPantalla(tester);

      await llenarFormulario(tester, correo: 'anacorreo.com');
      await tocarCrearCuenta(tester);

      expect(
        find.text('Formato inválido. Ejemplo: tucorreo@ejemplo.com'),
        findsOneWidget,
      );
      verificarQueNoLlamoAlService();
    });
  });

  group('Criterio 4 — contraseña inválida', () {
    testWidgets('marca el campo y no llama al service', (tester) async {
      await abrirPantalla(tester);

      await llenarFormulario(tester, password: 'Abcdefgh!');
      await tocarCrearCuenta(tester);

      expect(find.text('Debe incluir al menos un número'), findsOneWidget);
      verificarQueNoLlamoAlService();
    });
  });

  group('Otros errores', () {
    testWidgets('muestra el título y mensaje que manda el service', (
      tester,
    ) async {
      cuandoRegistrar().thenThrow(
        const RegistroException(
          titulo: 'Sin conexión',
          mensaje: 'Revisa tu internet.',
        ),
      );
      await abrirPantalla(tester);

      await llenarFormulario(tester);
      await tocarCrearCuenta(tester);

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Revisa tu internet.'), findsOneWidget);
    });
  });
}
