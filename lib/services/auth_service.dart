import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../google_config.dart';

/// El correo ya pertenece a otra cuenta.
class CorreoYaRegistradoException implements Exception {}

/// Cualquier otro fallo al registrar. Trae los textos listos para una alerta.
class RegistroException implements Exception {
  const RegistroException({required this.titulo, required this.mensaje});

  final String titulo;
  final String mensaje;
}

/// Correo no registrado o contraseña incorrecta. Supabase no distingue entre
/// los dos a propósito, para que nadie averigüe qué correos tienen cuenta.
class CredencialesInvalidasException implements Exception {}

/// Cualquier otro fallo al iniciar sesión. Trae los textos listos para una
/// alerta.
class InicioSesionException implements Exception {
  const InicioSesionException({required this.titulo, required this.mensaje});

  final String titulo;
  final String mensaje;
}

/// Fallo al pedir o usar el código de recuperación. Trae los textos listos
/// para una alerta.
class RecuperacionException implements Exception {
  const RecuperacionException({required this.titulo, required this.mensaje});

  final String titulo;
  final String mensaje;
}

/// Cómo obtiene la app el servicio de autenticación. Las pruebas lo
/// reemplazan con `overrideWithValue`.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class AuthService {
  /// En la app se usa el cliente real. Las pruebas pasan uno simulado, porque
  /// ahí Supabase no está inicializado.
  AuthService({GoTrueClient? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? Supabase.instance.client.auth,
      // serverClientId: el pase de Google va dirigido al cliente web, que es
      // el que Supabase tiene configurado para verificarlo.
      _googleSignIn =
          googleSignIn ??
          GoogleSignIn(serverClientId: GoogleConfig.webClientId);

  final GoTrueClient _auth;
  final GoogleSignIn _googleSignIn;

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

  /// Inicia sesión con correo y contraseña. Si sale bien, Supabase guarda la
  /// sesión en el dispositivo: la próxima vez que se abra la app sigue abierta.
  Future<void> iniciarSesion({
    required String correo,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(email: correo, password: password);
    } on AuthRetryableFetchException {
      throw const InicioSesionException(
        titulo: 'Sin conexión',
        mensaje:
            'No pudimos conectarnos. Revisa tu internet e inténtalo de nuevo.',
      );
    } on AuthException catch (e) {
      // "invalid_credentials" no está en el enum de esta versión del paquete;
      // servidores más viejos solo mandan el texto, sin código.
      if (e.code == 'invalid_credentials' ||
          e.message == 'Invalid login credentials') {
        throw CredencialesInvalidasException();
      }

      throw switch (e.code) {
        'email_not_confirmed' => const InicioSesionException(
          titulo: 'Confirma tu correo',
          mensaje:
              'Abre el enlace que te enviamos al registrarte y vuelve a '
              'intentarlo.',
        ),
        'user_banned' => const InicioSesionException(
          titulo: 'Cuenta suspendida',
          mensaje: 'Tu cuenta está suspendida. Contacta al equipo de TRAZA.',
        ),
        'over_request_rate_limit' => const InicioSesionException(
          titulo: 'Demasiados intentos',
          mensaje: 'Espera unos minutos y vuelve a intentarlo.',
        ),
        _ => const InicioSesionException(
          titulo: 'No pudimos iniciar sesión',
          mensaje: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      };
    }
  }

  /// Pide a Supabase que envíe el código de recuperación al correo. Supabase
  /// responde igual exista o no la cuenta, para no revelar qué correos están
  /// registrados.
  Future<void> solicitarRecuperacion({required String correo}) async {
    try {
      await _auth.resetPasswordForEmail(correo);
    } on AuthRetryableFetchException {
      throw const RecuperacionException(
        titulo: 'Sin conexión',
        mensaje:
            'No pudimos conectarnos. Revisa tu internet e inténtalo de nuevo.',
      );
    } on AuthException catch (e) {
      throw switch (e.code) {
        'over_email_send_rate_limit' ||
        'over_request_rate_limit' => const RecuperacionException(
          titulo: 'Demasiados intentos',
          mensaje: 'Espera un minuto y vuelve a intentarlo.',
        ),
        _ => const RecuperacionException(
          titulo: 'No pudimos enviar el código',
          mensaje: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      };
    }
  }

  /// Verifica el código de recuperación. Si es correcto, Supabase abre una
  /// sesión temporal que permite cambiar la contraseña. El código se gasta al
  /// verificarlo: no se puede usar dos veces.
  Future<void> verificarCodigoRecuperacion({
    required String correo,
    required String codigo,
  }) async {
    try {
      await _auth.verifyOTP(
        type: OtpType.recovery,
        email: correo,
        token: codigo,
      );
    } on AuthRetryableFetchException {
      throw const RecuperacionException(
        titulo: 'Sin conexión',
        mensaje:
            'No pudimos conectarnos. Revisa tu internet e inténtalo de nuevo.',
      );
    } on AuthException catch (e) {
      throw switch (e.code) {
        // Supabase usa el mismo código para "vencido" y para "incorrecto".
        'otp_expired' => const RecuperacionException(
          titulo: 'Código no válido',
          mensaje: 'El código es incorrecto o ya venció. Pide uno nuevo.',
        ),
        'over_request_rate_limit' => const RecuperacionException(
          titulo: 'Demasiados intentos',
          mensaje: 'Espera unos minutos y vuelve a intentarlo.',
        ),
        _ => const RecuperacionException(
          titulo: 'No pudimos verificar el código',
          mensaje: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      };
    }
  }

  /// Cambia la contraseña de la sesión abierta por [verificarCodigoRecuperacion].
  Future<void> cambiarPassword({required String nuevaPassword}) async {
    try {
      await _auth.updateUser(UserAttributes(password: nuevaPassword));
    } on AuthRetryableFetchException {
      throw const RecuperacionException(
        titulo: 'Sin conexión',
        mensaje:
            'No pudimos conectarnos. Revisa tu internet e inténtalo de nuevo.',
      );
    } on AuthException catch (e) {
      throw switch (e.code) {
        'same_password' => const RecuperacionException(
          titulo: 'Usa otra contraseña',
          mensaje: 'La nueva contraseña tiene que ser distinta a la anterior.',
        ),
        'weak_password' => const RecuperacionException(
          titulo: 'Contraseña no permitida',
          mensaje: 'Esa contraseña no es segura. Prueba con una distinta.',
        ),
        _ => const RecuperacionException(
          titulo: 'No pudimos cambiar tu contraseña',
          mensaje: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      };
    }
  }

  /// Abre la ventana de Google y, con el pase que devuelve, inicia sesión en
  /// Supabase. Si es la primera vez, Supabase crea la cuenta y el trigger llena
  /// `perfiles` con el nombre de Google. Devuelve `false` si la persona cerró
  /// la ventana sin terminar: no es un error.
  Future<bool> iniciarSesionConGoogle() async {
    const errorGoogle = InicioSesionException(
      titulo: 'No pudimos conectar con Google',
      mensaje:
          'Inténtalo de nuevo. Si sigue pasando, avísale al equipo de TRAZA.',
    );
    const sinConexion = InicioSesionException(
      titulo: 'Sin conexión',
      mensaje:
          'No pudimos conectarnos. Revisa tu internet e inténtalo de nuevo.',
    );

    try {
      // Olvida la cuenta de la vez anterior para que Google siempre muestre
      // la lista y la persona pueda elegir con cuál entrar.
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final cuenta = await _googleSignIn.signIn();
      if (cuenta == null) return false;

      final autenticacion = await cuenta.authentication;
      final idToken = autenticacion.idToken;
      // Sin pase: el serverClientId no corresponde al cliente web.
      if (idToken == null) throw errorGoogle;

      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: autenticacion.accessToken,
      );
      return true;
    } on PlatformException catch (e) {
      if (e.code == GoogleSignIn.kSignInCanceledError) return false;
      // "sign_in_failed" con "ApiException: 10" es casi siempre la SHA-1 de
      // este computador sin registrar en el cliente Android de Google Cloud.
      debugPrint('Google Sign-In falló: ${e.code} ${e.message}');
      throw e.code == GoogleSignIn.kNetworkError ? sinConexion : errorGoogle;
    } on AuthRetryableFetchException {
      throw sinConexion;
    } on AuthException catch (e) {
      debugPrint('Supabase rechazó el pase de Google: ${e.code} ${e.message}');
      throw errorGoogle;
    }
  }

  /// Cierra la sesión. Si falla la red, Supabase igual borra la sesión del
  /// dispositivo, así que el error no se propaga.
  Future<void> cerrarSesion() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('No se pudo cerrar la sesión en el servidor: $e');
    }
    // También en Google: si no, la próxima vez entraría directo con la misma
    // cuenta, sin dejar elegir otra.
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('No se pudo cerrar la sesión de Google: $e');
    }
  }
}
