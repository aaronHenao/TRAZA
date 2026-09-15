import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_login.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/inicio_google_provider.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Pruebas del resultado del inicio de sesión con Google, sin pantalla.
void main() {
  late _MockAuthService auth;
  late ProviderContainer contenedor;

  setUp(() {
    auth = _MockAuthService();
    contenedor = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(contenedor.dispose);
    // inicioGoogleProvider es autoDispose: esto lo mantiene vivo.
    contenedor.listen(inicioGoogleProvider, (_, _) {});
  });

  Future<void> iniciar() =>
      contenedor.read(inicioGoogleProvider.notifier).iniciar();

  EstadoLogin estado() => contenedor.read(inicioGoogleProvider);

  test('criterios 1 y 4: entró', () async {
    when(
      () => auth.iniciarSesionConGoogle(),
    ).thenAnswer((_) async => ResultadoInicioGoogle.cuentaExistente);

    await iniciar();

    expect(estado().fase, FaseLogin.exito);
    expect(estado().primerAcceso, isFalse);
  });

  test('SCRUM-60: primer acceso queda marcado', () async {
    when(
      () => auth.iniciarSesionConGoogle(),
    ).thenAnswer((_) async => ResultadoInicioGoogle.cuentaNueva);

    await iniciar();

    expect(estado().fase, FaseLogin.exito);
    expect(estado().primerAcceso, isTrue);
  });

  test('criterio 5: cerró la ventana, vuelve al inicio sin error', () async {
    when(
      () => auth.iniciarSesionConGoogle(),
    ).thenAnswer((_) async => ResultadoInicioGoogle.cancelado);

    await iniciar();

    expect(estado().fase, FaseLogin.inicial);
  });

  test('error: publica título y mensaje', () async {
    when(() => auth.iniciarSesionConGoogle()).thenThrow(
      const InicioSesionException(
        titulo: 'Sin conexión',
        mensaje: 'Revisa tu internet.',
      ),
    );

    await iniciar();

    expect(estado().fase, FaseLogin.error);
    expect(estado().tituloError, 'Sin conexión');
  });
}
