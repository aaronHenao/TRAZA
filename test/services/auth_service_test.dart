import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

/// Google falso: simula la ventana de elegir cuenta sin abrir nada.
class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockCuentaGoogle extends Mock implements GoogleSignInAccount {}

class _MockAutenticacionGoogle extends Mock
    implements GoogleSignInAuthentication {}

void main() {
  late _MockGoTrueClient auth;
  late _MockGoogleSignIn google;
  late AuthService servicio;

  setUp(() {
    auth = _MockGoTrueClient();
    google = _MockGoogleSignIn();
    servicio = AuthService(auth: auth, googleSignIn: google);
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

  group('restablecer contraseña (SCRUM-74)', () {
    // mocktail necesita un valor de ejemplo para usar any() con este tipo.
    setUpAll(() => registerFallbackValue(UserAttributes()));

    Matcher lanzaRecuperacionException(String titulo) {
      return throwsA(
        isA<RecuperacionException>().having((e) => e.titulo, 'titulo', titulo),
      );
    }

    When<Future<AuthResponse>> cuandoVerificar() {
      return when(
        () => auth.verifyOTP(
          type: OtpType.recovery,
          email: any(named: 'email'),
          token: any(named: 'token'),
        ),
      );
    }

    test('verifica el código como código de recuperación', () async {
      cuandoVerificar().thenAnswer((_) async => AuthResponse());

      await servicio.verificarCodigoRecuperacion(
        correo: 'ana@correo.com',
        codigo: '123456',
      );

      verify(
        () => auth.verifyOTP(
          type: OtpType.recovery,
          email: 'ana@correo.com',
          token: '123456',
        ),
      ).called(1);
    });

    test('código incorrecto o vencido', () async {
      cuandoVerificar().thenThrow(
        const AuthApiException('expired', code: 'otp_expired'),
      );

      await expectLater(
        servicio.verificarCodigoRecuperacion(
          correo: 'ana@correo.com',
          codigo: '000000',
        ),
        lanzaRecuperacionException('Código no válido'),
      );
    });

    test('cambia la contraseña con updateUser', () async {
      when(
        () => auth.updateUser(any()),
      ).thenAnswer((_) async => UserResponse.fromJson({}));

      await servicio.cambiarPassword(nuevaPassword: 'Nueva123!');

      final atributos =
          verify(() => auth.updateUser(captureAny())).captured.single
              as UserAttributes;
      expect(atributos.password, 'Nueva123!');
    });

    test('contraseña igual a la anterior', () async {
      when(
        () => auth.updateUser(any()),
      ).thenThrow(const AuthApiException('same', code: 'same_password'));

      await expectLater(
        servicio.cambiarPassword(nuevaPassword: 'Vieja123!'),
        lanzaRecuperacionException('Usa otra contraseña'),
      );
    });
  });

  group('cerrarSesion (SCRUM-75)', () {
    test('cierra la sesión en Supabase', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});

      await servicio.cerrarSesion();

      verify(() => auth.signOut()).called(1);
    });

    test('si falla la red, no lanza el error', () async {
      when(() => auth.signOut()).thenThrow(AuthRetryableFetchException());

      await expectLater(servicio.cerrarSesion(), completes);
    });

    test('también cierra la sesión de Google', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      when(() => google.signOut()).thenAnswer((_) async => null);

      await servicio.cerrarSesion();

      verify(() => google.signOut()).called(1);
    });
  });

  group('iniciarSesionConGoogle (SCRUM-68 y SCRUM-69)', () {
    Matcher lanzaInicioSesionException(String titulo) {
      return throwsA(
        isA<InicioSesionException>().having((e) => e.titulo, 'titulo', titulo),
      );
    }

    void verificarQueNoLlamoASupabase() {
      verifyNever(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: any(named: 'idToken'),
          accessToken: any(named: 'accessToken'),
        ),
      );
    }

    /// Simula que Google entrega un pase y Supabase responde con [usuario].
    void cuandoGoogleEntraCon(User? usuario) {
      final cuenta = _MockCuentaGoogle();
      final autenticacion = _MockAutenticacionGoogle();
      when(() => google.signIn()).thenAnswer((_) async => cuenta);
      when(() => cuenta.authentication).thenAnswer((_) async => autenticacion);
      when(() => autenticacion.idToken).thenReturn('pase-de-google');
      when(() => autenticacion.accessToken).thenReturn('acceso');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'pase-de-google',
          accessToken: 'acceso',
        ),
      ).thenAnswer((_) async => AuthResponse(user: usuario));
    }

    User usuarioGoogle({Map<String, dynamic> metadatos = const {}}) {
      return User(
        id: 'usuario-google',
        appMetadata: const {},
        userMetadata: metadatos,
        aud: 'authenticated',
        createdAt: _fecha,
      );
    }

    test('ya terminó Perfil y Permisos: va a Inicio', () async {
      cuandoGoogleEntraCon(
        usuarioGoogle(metadatos: {'onboarding_completado': true}),
      );

      expect(
        await servicio.iniciarSesionConGoogle(),
        ResultadoInicioGoogle.onboardingCompleto,
      );
    });

    test('SCRUM-60: cuenta nueva, sin la marca, va a Perfil', () async {
      cuandoGoogleEntraCon(usuarioGoogle());

      expect(
        await servicio.iniciarSesionConGoogle(),
        ResultadoInicioGoogle.onboardingPendiente,
      );
    });

    test('siempre muestra la lista de cuentas: olvida la anterior', () async {
      when(() => google.signOut()).thenAnswer((_) async => null);
      when(() => google.signIn()).thenAnswer((_) async => null);

      await servicio.iniciarSesionConGoogle();

      verifyInOrder([() => google.signOut(), () => google.signIn()]);
    });

    test('cerró la ventana de Google: no es error', () async {
      when(() => google.signIn()).thenAnswer((_) async => null);

      expect(
        await servicio.iniciarSesionConGoogle(),
        ResultadoInicioGoogle.cancelado,
      );
      verificarQueNoLlamoASupabase();
    });

    test('Google avisa cancelación: no es error', () async {
      when(
        () => google.signIn(),
      ).thenThrow(PlatformException(code: GoogleSignIn.kSignInCanceledError));

      expect(
        await servicio.iniciarSesionConGoogle(),
        ResultadoInicioGoogle.cancelado,
      );
    });

    test('sin conexión', () async {
      when(
        () => google.signIn(),
      ).thenThrow(PlatformException(code: GoogleSignIn.kNetworkError));

      await expectLater(
        servicio.iniciarSesionConGoogle(),
        lanzaInicioSesionException('Sin conexión'),
      );
    });

    test('Google falla (por ejemplo, SHA-1 sin registrar)', () async {
      when(() => google.signIn()).thenThrow(
        PlatformException(
          code: GoogleSignIn.kSignInFailedError,
          message: 'ApiException: 10',
        ),
      );

      await expectLater(
        servicio.iniciarSesionConGoogle(),
        lanzaInicioSesionException('No pudimos conectar con Google'),
      );
      verificarQueNoLlamoASupabase();
    });
  });

  group('onboarding (SCRUM-81)', () {
    User usuario(Map<String, dynamic> metadatos) => User(
      id: 'usuario-1',
      appMetadata: const {},
      userMetadata: metadatos,
      aud: 'authenticated',
      createdAt: _fecha,
    );

    test('sin la marca en los metadatos, lo requiere', () {
      when(() => auth.currentUser).thenReturn(usuario(const {}));
      expect(servicio.requiereOnboarding, isTrue);
    });

    test('con la marca, ya no', () {
      when(
        () => auth.currentUser,
      ).thenReturn(usuario(const {'onboarding_completado': true}));
      expect(servicio.requiereOnboarding, isFalse);
    });

    test('sin sesión no aplica', () {
      expect(AuthService.requiereOnboardingDe(null), isFalse);
    });

    test('completarlo guarda la marca en los metadatos', () async {
      registerFallbackValue(UserAttributes());
      when(
        () => auth.updateUser(any()),
      ).thenAnswer((_) async => UserResponse.fromJson(const {}));

      await servicio.completarOnboarding();

      final atributos =
          verify(() => auth.updateUser(captureAny())).captured.single
              as UserAttributes;
      expect(atributos.data, {'onboarding_completado': true});
    });

    test('si falla la red, no lanza el error', () async {
      registerFallbackValue(UserAttributes());
      when(
        () => auth.updateUser(any()),
      ).thenThrow(AuthRetryableFetchException());

      await expectLater(servicio.completarOnboarding(), completes);
    });
  });
}
