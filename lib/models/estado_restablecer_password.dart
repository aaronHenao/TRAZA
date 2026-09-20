import 'package:flutter/foundation.dart';

/// En qué punto está el cambio de contraseña con el código de recuperación.
enum FaseRestablecerPassword { inicial, enviando, exito, error }

@immutable
class EstadoRestablecerPassword {
  const EstadoRestablecerPassword.inicial()
    : fase = FaseRestablecerPassword.inicial,
      tituloError = null,
      mensajeError = null;

  const EstadoRestablecerPassword.enviando()
    : fase = FaseRestablecerPassword.enviando,
      tituloError = null,
      mensajeError = null;

  const EstadoRestablecerPassword.exito()
    : fase = FaseRestablecerPassword.exito,
      tituloError = null,
      mensajeError = null;

  const EstadoRestablecerPassword.error({
    required String this.tituloError,
    required String this.mensajeError,
  }) : fase = FaseRestablecerPassword.error;

  final FaseRestablecerPassword fase;
  final String? tituloError;
  final String? mensajeError;

  bool get enviando => fase == FaseRestablecerPassword.enviando;
}
