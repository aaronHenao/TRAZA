import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/screens/auth/forgot_password_screen.dart';
import 'package:traza/screens/auth/login_screen.dart';
import 'package:traza/services/auth_service.dart';

import '../../utils/app_de_prueba.dart';

/// Service falso: la pantalla cree que habla con Supabase, pero no hay red.
class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAuthService auth;

  setUp(() => auth = _MockAuthService());

  When<Future<void>> cuandoIniciarSesion() {
    return when(
      () => auth.iniciarSesion(
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

    await tester.pumpWidget(appDePrueba(auth: auth, ruta: '/login'));
  }

  Future<void> llenarFormulario(WidgetTester tester) async {
    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), '  ana@correo.com  ');
    await tester.enterText(campos.at(1), 'clave mala');
  }

  Future<void> tocarIniciarSesion(WidgetTester tester) async {
    // Se busca dentro del botón: el título dice "Inicia sesión", muy parecido.
    final boton = find.widgetWithText(FilledButton, 'Iniciar sesión');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  group('Criterio 1 — inicio de sesión exitoso', () {
    testWidgets('envía el correo sin espacios y va a Inicio (SCRUM-66)', (
      tester,
    ) async {
      cuandoIniciarSesion().thenAnswer((_) async {});
      await abrirPantalla(tester);

      await llenarFormulario(tester);
      await tocarIniciarSesion(tester);

      verify(
        () => auth.iniciarSesion(
          correo: 'ana@correo.com',
          password: 'clave mala',
        ),
      ).called(1);
      expect(find.text('Pantalla Inicio'), findsOneWidget);
    });
  });

  group('Criterios 2 y 3 — credenciales no válidas', () {
    testWidgets('muestra la alerta con el botón de recuperar contraseña', (
      tester,
    ) async {
      cuandoIniciarSesion().thenThrow(CredencialesInvalidasException());
      await abrirPantalla(tester);

      await llenarFormulario(tester);
      await tocarIniciarSesion(tester);

      expect(find.text('Credenciales no válidas'), findsOneWidget);
      expect(find.text('Recuperar contraseña'), findsOneWidget);
    });

    testWidgets('"Recuperar contraseña" cierra la alerta y abre la pantalla', (
      tester,
    ) async {
      cuandoIniciarSesion().thenThrow(CredencialesInvalidasException());
      await abrirPantalla(tester);

      await llenarFormulario(tester);
      await tocarIniciarSesion(tester);
      await tester.tap(find.text('Recuperar contraseña'));
      await tester.pumpAndSettle();

      expect(find.text('Credenciales no válidas'), findsNothing);
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });
  });

  group('SCRUM-65 — acceso a recuperación de contraseña', () {
    testWidgets('el enlace abre la pantalla con el correo ya escrito', (
      tester,
    ) async {
      await abrirPantalla(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'ana@correo.com',
      );
      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.textContaining('ana@correo.com'), findsOneWidget);
    });

    // Demuestra el push: después de volver, el login sigue en la pila.
    testWidgets('"Volver a iniciar sesión" regresa al login', (tester) async {
      await abrirPantalla(tester);

      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volver a iniciar sesión'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('SCRUM-68 — inicio de sesión con Google', () {
    Future<void> tocarGoogle(WidgetTester tester) async {
      final boton = find.text('Continuar con Google');
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      await tester.pumpAndSettle();
    }

    testWidgets('ya tenía cuenta: va a Inicio (SCRUM-70)', (tester) async {
      when(
        () => auth.iniciarSesionConGoogle(),
      ).thenAnswer((_) async => ResultadoInicioGoogle.cuentaExistente);
      await abrirPantalla(tester);

      await tocarGoogle(tester);

      expect(find.text('Pantalla Inicio'), findsOneWidget);
    });

    testWidgets('primer acceso: va a Perfil (SCRUM-60)', (tester) async {
      when(
        () => auth.iniciarSesionConGoogle(),
      ).thenAnswer((_) async => ResultadoInicioGoogle.cuentaNueva);
      await abrirPantalla(tester);

      await tocarGoogle(tester);

      expect(find.text('Pantalla Perfil'), findsOneWidget);
    });

    testWidgets('canceló: no muestra nada', (tester) async {
      when(
        () => auth.iniciarSesionConGoogle(),
      ).thenAnswer((_) async => ResultadoInicioGoogle.cancelado);
      await abrirPantalla(tester);

      await tocarGoogle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('error: muestra la alerta', (tester) async {
      when(() => auth.iniciarSesionConGoogle()).thenThrow(
        const InicioSesionException(
          titulo: 'No pudimos conectar con Google',
          mensaje: 'Inténtalo de nuevo.',
        ),
      );
      await abrirPantalla(tester);

      await tocarGoogle(tester);

      expect(find.text('No pudimos conectar con Google'), findsOneWidget);
    });
  });

  group('Criterio 4 — campos vacíos', () {
    testWidgets('marca los dos campos y no llama al service', (tester) async {
      await abrirPantalla(tester);

      await tocarIniciarSesion(tester);

      expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
      expect(find.text('Ingresa tu contraseña'), findsOneWidget);
      verifyNever(
        () => auth.iniciarSesion(
          correo: any(named: 'correo'),
          password: any(named: 'password'),
        ),
      );
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

  group('Otros errores', () {
    testWidgets('muestra el título y mensaje que manda el service', (
      tester,
    ) async {
      cuandoIniciarSesion().thenThrow(
        const InicioSesionException(
          titulo: 'Confirma tu correo',
          mensaje: 'Abre el enlace que te enviamos.',
        ),
      );
      await abrirPantalla(tester);

      await llenarFormulario(tester);
      await tocarIniciarSesion(tester);

      expect(find.text('Confirma tu correo'), findsOneWidget);
      expect(find.text('Abre el enlace que te enviamos.'), findsOneWidget);
    });
  });
}
