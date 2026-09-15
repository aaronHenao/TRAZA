import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_restablecer_password.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/restablecer_password_provider.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Pruebas de la lógica de restablecer la contraseña, sin pantalla.
void main() {
  late _MockAuthService auth;
  late ProviderContainer contenedor;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.cerrarSesion()).thenAnswer((_) async {});
    contenedor = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(contenedor.dispose);

    // restablecerPasswordProvider es autoDispose: esto lo mantiene vivo.
    contenedor.listen(restablecerPasswordProvider, (_, _) {});
  });

  When<Future<void>> cuandoVerificar() {
    return when(
      () => auth.verificarCodigoRecuperacion(
        correo: any(named: 'correo'),
        codigo: any(named: 'codigo'),
      ),
    );
  }

  When<Future<void>> cuandoCambiar() {
    return when(
      () => auth.cambiarPassword(nuevaPassword: any(named: 'nuevaPassword')),
    );
  }

  Future<void> restablecer() {
    return contenedor
        .read(restablecerPasswordProvider.notifier)
        .restablecer(
          correo: 'ana@correo.com',
          codigo: '123456',
          nuevaPassword: 'Nueva123!',
        );
  }

  EstadoRestablecerPassword estado() =>
      contenedor.read(restablecerPasswordProvider);

  test('verifica el código y cambia la contraseña', () async {
    cuandoVerificar().thenAnswer((_) async {});
    cuandoCambiar().thenAnswer((_) async {});

    await restablecer();

    expect(estado().fase, FaseRestablecerPassword.exito);
    verify(
      () => auth.verificarCodigoRecuperacion(
        correo: 'ana@correo.com',
        codigo: '123456',
      ),
    ).called(1);
    verify(() => auth.cambiarPassword(nuevaPassword: 'Nueva123!')).called(1);
  });

  test('si el código falla, no intenta cambiar la contraseña', () async {
    cuandoVerificar().thenThrow(
      const RecuperacionException(
        titulo: 'Código no válido',
        mensaje: 'Pide uno nuevo.',
      ),
    );

    await restablecer();

    expect(estado().fase, FaseRestablecerPassword.error);
    expect(estado().tituloError, 'Código no válido');
    verifyNever(
      () => auth.cambiarPassword(nuevaPassword: any(named: 'nuevaPassword')),
    );
  });

  // El código se gasta al verificarlo: reintentar no debe volver a verificarlo.
  test(
    'al reintentar tras fallar la contraseña, no verifica otra vez',
    () async {
      cuandoVerificar().thenAnswer((_) async {});
      cuandoCambiar().thenThrow(
        const RecuperacionException(
          titulo: 'Usa otra contraseña',
          mensaje: 'Tiene que ser distinta.',
        ),
      );

      await restablecer();
      expect(estado().tituloError, 'Usa otra contraseña');

      cuandoCambiar().thenAnswer((_) async {});
      await restablecer();

      expect(estado().fase, FaseRestablecerPassword.exito);
      verify(
        () => auth.verificarCodigoRecuperacion(
          correo: any(named: 'correo'),
          codigo: any(named: 'codigo'),
        ),
      ).called(1);
    },
  );

  group('SCRUM-75 — sesión temporal', () {
    test('cierra la sesión después de cambiar la contraseña', () async {
      cuandoVerificar().thenAnswer((_) async {});
      cuandoCambiar().thenAnswer((_) async {});

      await restablecer();

      verify(() => auth.cerrarSesion()).called(1);
    });

    test('si se sale tras verificar el código, cierra la sesión', () async {
      cuandoVerificar().thenAnswer((_) async {});
      cuandoCambiar().thenThrow(
        const RecuperacionException(
          titulo: 'Usa otra contraseña',
          mensaje: 'Tiene que ser distinta.',
        ),
      );

      await restablecer();
      contenedor.dispose(); // la persona cerró la pantalla

      verify(() => auth.cerrarSesion()).called(1);
    });

    test('si se sale sin verificar el código, no toca la sesión', () async {
      contenedor.dispose();

      verifyNever(() => auth.cerrarSesion());
    });
  });
}
