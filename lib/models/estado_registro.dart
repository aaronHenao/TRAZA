import 'package:flutter/foundation.dart';

/// En qué punto está el envío del formulario de registro.
enum FaseRegistro {
  /// El usuario todavía no ha enviado el formulario.
  inicial,

  /// Se espera la respuesta de Supabase: el botón muestra el spinner.
  enviando,

  /// La cuenta se creó.
  exito,

  /// Supabase o la red respondieron con un error.
  error,
}

/// Instantánea inmutable del registro que consume la pantalla.
///
/// Cada constructor corresponde a una fase, así un estado nunca mezcla datos
/// de éxito con datos de error.
@immutable
class EstadoRegistro {
  const EstadoRegistro.inicial()
    : fase = FaseRegistro.inicial,
      correo = null,
      requiereConfirmacion = false,
      tituloError = null,
      mensajeError = null;

  const EstadoRegistro.enviando()
    : fase = FaseRegistro.enviando,
      correo = null,
      requiereConfirmacion = false,
      tituloError = null,
      mensajeError = null;

  const EstadoRegistro.exito({
    required String this.correo,
    required this.requiereConfirmacion,
  }) : fase = FaseRegistro.exito,
       tituloError = null,
       mensajeError = null;

  const EstadoRegistro.error({
    required String this.tituloError,
    required String this.mensajeError,
  }) : fase = FaseRegistro.error,
       correo = null,
       requiereConfirmacion = false;

  final FaseRegistro fase;

  /// Correo con el que se creó la cuenta. Solo en [FaseRegistro.exito].
  final String? correo;

  /// Si hay que confirmar el correo antes de iniciar sesión. Solo en éxito.
  final bool requiereConfirmacion;

  /// Textos de la alerta. Solo en [FaseRegistro.error].
  final String? tituloError;
  final String? mensajeError;

  bool get enviando => fase == FaseRegistro.enviando;
}
