import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_login.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/login_provider.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Pruebas de la lógica del inicio de sesión, sin pantalla.
void main() {
  late _MockAuthService auth;
  late ProviderContainer contenedor;

  setUp(() {
    auth = _MockAuthService();
    contenedor = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(contenedor.dispose);

    // loginProvider es autoDispose: este listener lo mantiene vivo.
    contenedor.listen(loginProvider, (_, _) {});
  });

  When<Future<void>> cuandoIniciarSesion() {
    return when(
      () => auth.iniciarSesion(
        correo: any(named: 'correo'),
        password: any(named: 'password'),
      ),
    );
  }

  Future<void> iniciarSesion() {
    return contenedor
        .read(loginProvider.notifier)
        .iniciarSesion(correo: 'ana@correo.com', password: 'Abcdefg1!');
  }

  EstadoLogin estado() => contenedor.read(loginProvider);

  test('arranca en la fase inicial', () {
    expect(estado().fase, FaseLogin.inicial);
  });

  test('queda en enviando mientras espera la respuesta', () async {
    final respuesta = Completer<void>();
    cuandoIniciarSesion().thenAnswer((_) => respuesta.future);

    final envio = iniciarSesion();
    expect(estado().enviando, isTrue);

    respuesta.complete();
    await envio;
    expect(estado().enviando, isFalse);
  });

  test('ignora un segundo envío mientras el primero sigue en curso', () async {
    final respuesta = Completer<void>();
    cuandoIniciarSesion().thenAnswer((_) => respuesta.future);

    final primero = iniciarSesion();
    final segundo = iniciarSesion();
    respuesta.complete();
    await Future.wait([primero, segundo]);

    verify(
      () => auth.iniciarSesion(
        correo: any(named: 'correo'),
        password: any(named: 'password'),
      ),
    ).called(1);
  });

  test('criterio 1: publica el éxito', () async {
    cuandoIniciarSesion().thenAnswer((_) async {});

    await iniciarSesion();

    expect(estado().fase, FaseLogin.exito);
  });

  test('criterios 2 y 3: publica credenciales inválidas', () async {
    cuandoIniciarSesion().thenThrow(CredencialesInvalidasException());

    await iniciarSesion();

    expect(estado().fase, FaseLogin.credencialesInvalidas);
  });

  test('usa el título y mensaje que manda el service', () async {
    cuandoIniciarSesion().thenThrow(
      const InicioSesionException(
        titulo: 'Confirma tu correo',
        mensaje: 'Abre el enlace.',
      ),
    );

    await iniciarSesion();

    expect(estado().fase, FaseLogin.error);
    expect(estado().tituloError, 'Confirma tu correo');
    expect(estado().mensajeError, 'Abre el enlace.');
  });

  test('un error que no es de Supabase muestra el mensaje genérico', () async {
    cuandoIniciarSesion().thenThrow(StateError('algo raro'));

    await iniciarSesion();

    expect(estado().tituloError, 'Algo salió mal');
  });
}
