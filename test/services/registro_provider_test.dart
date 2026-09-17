import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_registro.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/registro_provider.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Pruebas de la lógica del registro, sin pantalla: un ProviderContainer es
/// el ProviderScope de las pruebas que no dibujan widgets.
void main() {
  late _MockAuthService auth;
  late ProviderContainer contenedor;

  setUp(() {
    auth = _MockAuthService();
    contenedor = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(contenedor.dispose);

    // registroProvider es autoDispose: sin nadie escuchándolo se destruiría
    // entre una lectura y otra. Este listener lo mantiene vivo.
    contenedor.listen(registroProvider, (_, _) {});
  });

  When<Future<bool>> cuandoRegistrar() {
    return when(
      () => auth.registrar(
        nombre: any(named: 'nombre'),
        correo: any(named: 'correo'),
        password: any(named: 'password'),
      ),
    );
  }

  Future<void> registrar() {
    return contenedor
        .read(registroProvider.notifier)
        .registrar(
          nombre: 'Ana',
          correo: 'ana@correo.com',
          password: 'Abcdefg1!',
        );
  }

  EstadoRegistro estado() => contenedor.read(registroProvider);

  test('arranca en la fase inicial', () {
    expect(estado().fase, FaseRegistro.inicial);
  });

  test('queda en enviando mientras espera la respuesta', () async {
    final respuesta = Completer<bool>();
    cuandoRegistrar().thenAnswer((_) => respuesta.future);

    final envio = registrar();
    expect(estado().enviando, isTrue);

    respuesta.complete(true);
    await envio;
    expect(estado().enviando, isFalse);
  });

  test('ignora un segundo envío mientras el primero sigue en curso', () async {
    final respuesta = Completer<bool>();
    cuandoRegistrar().thenAnswer((_) => respuesta.future);

    final primero = registrar();
    final segundo = registrar();
    respuesta.complete(true);
    await Future.wait([primero, segundo]);

    verify(
      () => auth.registrar(
        nombre: any(named: 'nombre'),
        correo: any(named: 'correo'),
        password: any(named: 'password'),
      ),
    ).called(1);
  });

  group('Criterio 1 — cuenta creada', () {
    test('publica el éxito con el correo y si requiere confirmación', () async {
      cuandoRegistrar().thenAnswer((_) async => true);

      await registrar();

      expect(estado().fase, FaseRegistro.exito);
      expect(estado().correo, 'ana@correo.com');
      expect(estado().requiereConfirmacion, isTrue);
    });
  });

  group('Criterio 2 — correo ya registrado', () {
    test('publica el error con el mensaje del criterio', () async {
      cuandoRegistrar().thenThrow(CorreoYaRegistradoException());

      await registrar();

      expect(estado().fase, FaseRegistro.error);
      expect(estado().tituloError, 'Correo en uso');
      expect(
        estado().mensajeError,
        'El correo ingresado ya está asociado a una cuenta',
      );
    });
  });

  group('Otros errores', () {
    test('usa el título y mensaje que manda el service', () async {
      cuandoRegistrar().thenThrow(
        const RegistroException(titulo: 'Sin conexión', mensaje: 'Sin red.'),
      );

      await registrar();

      expect(estado().tituloError, 'Sin conexión');
      expect(estado().mensajeError, 'Sin red.');
    });

    test(
      'un error que no es de Supabase muestra el mensaje genérico',
      () async {
        cuandoRegistrar().thenThrow(StateError('algo raro'));

        await registrar();

        expect(estado().tituloError, 'Algo salió mal');
      },
    );
  });
}
