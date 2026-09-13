import 'package:supabase_flutter/supabase_flutter.dart';

/// El correo ya pertenece a otra cuenta.
class CorreoYaRegistradoException implements Exception {}

/// Cualquier otro fallo al registrar. Trae los textos listos para una alerta.
class RegistroException implements Exception {
  const RegistroException({required this.titulo, required this.mensaje});

  final String titulo;
  final String mensaje;
}

class AuthService {
  /// En la app se usa el cliente real. Las pruebas pasan uno simulado, porque
  /// ahí Supabase no está inicializado.
  AuthService({GoTrueClient? auth})
    : _auth = auth ?? Supabase.instance.client.auth;

  final GoTrueClient _auth;

  /// Crea la cuenta en Supabase Auth. Devuelve `true` si el usuario tiene que
  /// confirmar el correo antes de poder iniciar sesión.
  ///
  /// `data` aterriza en `auth.users.raw_user_meta_data`; de ahí el trigger
  /// `handle_new_user` (0002_perfiles.sql) toma `full_name` para llenar
  /// `perfiles.nombre`.
  Future<bool> registrar({
    required String nombre,
    required String correo,
    required String password,
  }) async {
    try {
      final respuesta = await _auth.signUp(
        email: correo,
        password: password,
        data: {'full_name': nombre},
      );

      // Con "Confirm email" encendido, Supabase no lanza error si el correo
      // ya existe: devuelve un usuario sin identidades.
      if (respuesta.user?.identities?.isEmpty ?? false) {
        throw CorreoYaRegistradoException();
      }

      // Sin sesión significa que Supabase espera la confirmación del correo.
      return respuesta.session == null;
    } on AuthRetryableFetchException {
      // Va antes que AuthException porque es una subclase suya.
      throw const RegistroException(
        titulo: 'Sin conexión',
        mensaje:
            'No pudimos conectarnos. Revisa tu internet e inténtalo de nuevo.',
      );
    } on AuthException catch (e) {
      throw switch (e.code) {
        'user_already_exists' ||
        'email_exists' => CorreoYaRegistradoException(),
        'over_email_send_rate_limit' ||
        'over_request_rate_limit' => const RegistroException(
          titulo: 'Demasiados intentos',
          mensaje: 'Espera unos minutos y vuelve a intentarlo.',
        ),
        'weak_password' => const RegistroException(
          titulo: 'Contraseña no permitida',
          mensaje: 'Esa contraseña no es segura. Prueba con una distinta.',
        ),
        // No está en el enum de esta versión del paquete, pero el servidor lo
        // envía, por ejemplo, con dominios de prueba como example.com.
        'email_address_invalid' => const RegistroException(
          titulo: 'Correo no válido',
          mensaje:
              'No podemos usar ese correo. Revisa que esté bien escrito o usa otro.',
        ),
        'validation_failed' => const RegistroException(
          titulo: 'Datos no válidos',
          mensaje: 'Revisa el correo y la contraseña e inténtalo de nuevo.',
        ),
        'signup_disabled' ||
        'email_provider_disabled' => const RegistroException(
          titulo: 'Registro no disponible',
          mensaje: 'El registro está desactivado en este momento.',
        ),
        'request_timeout' => const RegistroException(
          titulo: 'Sin respuesta',
          mensaje:
              'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
        ),
        _ => const RegistroException(
          titulo: 'No pudimos crear tu cuenta',
          mensaje: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      };
    }
  }
}
