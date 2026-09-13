import 'package:flutter/foundation.dart';

/// En qué punto está el inicio de sesión.
enum FaseLogin {
  /// El usuario todavía no ha enviado el formulario.
  inicial,

  /// Se espera la respuesta de Supabase: el botón muestra el spinner.
  enviando,

  /// La sesión quedó iniciada.
  exito,

  /// Correo no registrado o contraseña incorrecta (criterios 2 y 3).
  credencialesInvalidas,

  /// Cualquier otro error: sin conexión, correo sin confirmar, etc.
  error,
}

/// Instantánea inmutable del inicio de sesión que consume la pantalla.
@immutable
class EstadoLogin {
  const EstadoLogin.inicial()
    : fase = FaseLogin.inicial,
      tituloError = null,
      mensajeError = null;

  const EstadoLogin.enviando()
    : fase = FaseLogin.enviando,
      tituloError = null,
      mensajeError = null;

  const EstadoLogin.exito()
    : fase = FaseLogin.exito,
      tituloError = null,
      mensajeError = null;

  const EstadoLogin.credencialesInvalidas()
    : fase = FaseLogin.credencialesInvalidas,
      tituloError = null,
      mensajeError = null;

  const EstadoLogin.error({
    required String this.tituloError,
    required String this.mensajeError,
  }) : fase = FaseLogin.error;

  final FaseLogin fase;

  /// Textos de la alerta. Solo en [FaseLogin.error].
  final String? tituloError;
  final String? mensajeError;

  bool get enviando => fase == FaseLogin.enviando;
}
