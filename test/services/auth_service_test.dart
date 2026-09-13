import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/services/auth_service.dart';

/// Supabase Auth falso: responde lo que cada prueba le indique, sin red.
class _MockGoTrueClient extends Mock implements GoTrueClient {}

const _fecha = '2026-01-01T00:00:00Z';

User _usuario({required bool conIdentidades}) {
  return User(
    id: 'usuario-1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: _fecha,
    identities: conIdentidades
        ? const [
            UserIdentity(
              id: 'usuario-1',
              userId: 'usuario-1',
              identityData: {},
              identityId: 'identidad-1',
              provider: 'email',
              createdAt: _fecha,
              lastSignInAt: _fecha,
            ),
          ]
        : const [],
  );
}

void main() {
  late _MockGoTrueClient auth;
  late AuthService servicio;

  setUp(() {
    auth = _MockGoTrueClient();
    servicio = AuthService(auth: auth);
  });

  When<Future<AuthResponse>> cuandoSignUp() {
    return when(
      () => auth.signUp(
        email: any(named: 'email'),
        password: any(named: 'password'),
        data: any(named: 'data'),
      ),
    );
  }

  Future<bool> registrar() {
    return servicio.registrar(
      nombre: 'Ana',
      correo: 'ana@correo.com',
      password: 'Abcdefg1!',
    );
  }

  Matcher lanzaRegistroException(String titulo) {
    return throwsA(
      isA<RegistroException>().having((e) => e.titulo, 'titulo', titulo),
    );
  }

  group('Criterio 1 — cuenta creada', () {
    test('devuelve true cuando hay que confirmar el correo', () async {
      cuandoSignUp().thenAnswer(
        (_) async => AuthResponse(user: _usuario(conIdentidades: true)),
      );

      expect(await registrar(), isTrue);
    });

    test('devuelve false cuando no hace falta confirmar', () async {
      cuandoSignUp().thenAnswer(
        (_) async => AuthResponse(
          session: Session(
            accessToken: 'token',
            tokenType: 'bearer',
            user: _usuario(conIdentidades: true),
          ),
        ),
      );

      expect(await registrar(), isFalse);
    });

    test('envía el nombre en los metadatos para el trigger', () async {
      cuandoSignUp().thenAnswer(
        (_) async => AuthResponse(user: _usuario(conIdentidades: true)),
      );

      await registrar();

      verify(
        () => auth.signUp(
          email: 'ana@correo.com',
          password: 'Abcdefg1!',
          data: {'full_name': 'Ana'},
        ),
      ).called(1);
    });
  });

  group('Criterio 2 — correo ya registrado', () {
    test('con confirmación encendida: usuario sin identidades', () async {
      cuandoSignUp().thenAnswer(
        (_) async => AuthResponse(user: _usuario(conIdentidades: false)),
      );

      await expectLater(
        registrar(),
        throwsA(isA<CorreoYaRegistradoException>()),
      );
    });

    test('con confirmación apagada: código user_already_exists', () async {
      cuandoSignUp().thenThrow(
        const AuthApiException('exists', code: 'user_already_exists'),
      );

      await expectLater(
        registrar(),
        throwsA(isA<CorreoYaRegistradoException>()),
      );
    });

    test('código email_exists', () async {
      cuandoSignUp().thenThrow(
        const AuthApiException('exists', code: 'email_exists'),
      );

      await expectLater(
        registrar(),
        throwsA(isA<CorreoYaRegistradoException>()),
      );
    });
  });

  group('Otros errores', () {
    test('sin conexión', () async {
      cuandoSignUp().thenThrow(AuthRetryableFetchException());

      await expectLater(registrar(), lanzaRegistroException('Sin conexión'));
    });

    test('límite de envío de correos', () async {
      cuandoSignUp().thenThrow(
        const AuthApiException('limit', code: 'over_email_send_rate_limit'),
      );

      await expectLater(
        registrar(),
        lanzaRegistroException('Demasiados intentos'),
      );
    });

    test('contraseña rechazada por el servidor', () async {
      cuandoSignUp().thenThrow(
        const AuthApiException('weak', code: 'weak_password'),
      );

      await expectLater(
        registrar(),
        lanzaRegistroException('Contraseña no permitida'),
      );
    });

    test('código desconocido cae en el mensaje genérico', () async {
      cuandoSignUp().thenThrow(
        const AuthApiException('???', code: 'codigo_que_no_existe'),
      );

      await expectLater(
        registrar(),
        lanzaRegistroException('No pudimos crear tu cuenta'),
      );
    });
  });

  group('iniciarSesion (SCRUM-64)', () {
    When<Future<AuthResponse>> cuandoSignIn() {
      return when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    }

    Future<void> iniciarSesion() {
      return servicio.iniciarSesion(
        correo: 'ana@correo.com',
        password: 'Abcdefg1!',
      );
    }

    Matcher lanzaInicioSesionException(String titulo) {
      return throwsA(
        isA<InicioSesionException>().having((e) => e.titulo, 'titulo', titulo),
      );
    }

    test(
      'criterio 1: completa cuando las credenciales son correctas',
      () async {
        cuandoSignIn().thenAnswer((_) async => AuthResponse());

        await iniciarSesion();

        verify(
          () => auth.signInWithPassword(
            email: 'ana@correo.com',
            password: 'Abcdefg1!',
          ),
        ).called(1);
      },
    );

    test('criterios 2 y 3: código invalid_credentials', () async {
      cuandoSignIn().thenThrow(
        const AuthApiException('invalid', code: 'invalid_credentials'),
      );

      await expectLater(
        iniciarSesion(),
        throwsA(isA<CredencialesInvalidasException>()),
      );
    });

    test('criterios 2 y 3: servidor que solo manda el texto', () async {
      cuandoSignIn().thenThrow(
        const AuthApiException('Invalid login credentials'),
      );

      await expectLater(
        iniciarSesion(),
        throwsA(isA<CredencialesInvalidasException>()),
      );
    });

    test('correo sin confirmar', () async {
      cuandoSignIn().thenThrow(
        const AuthApiException('not confirmed', code: 'email_not_confirmed'),
      );

      await expectLater(
        iniciarSesion(),
        lanzaInicioSesionException('Confirma tu correo'),
      );
    });

    test('sin conexión', () async {
      cuandoSignIn().thenThrow(AuthRetryableFetchException());

      await expectLater(
        iniciarSesion(),
        lanzaInicioSesionException('Sin conexión'),
      );
    });

    test('código desconocido cae en el mensaje genérico', () async {
      cuandoSignIn().thenThrow(
        const AuthApiException('???', code: 'codigo_que_no_existe'),
      );

      await expectLater(
        iniciarSesion(),
        lanzaInicioSesionException('No pudimos iniciar sesión'),
      );
    });
  });
}
