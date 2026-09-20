import 'package:flutter/foundation.dart';

/// En qué punto está la solicitud del código de recuperación.
enum FaseSolicitudRecuperacion { inicial, enviando, enviado, error }

@immutable
class EstadoSolicitudRecuperacion {
  const EstadoSolicitudRecuperacion.inicial()
    : fase = FaseSolicitudRecuperacion.inicial,
      correo = null,
      tituloError = null,
      mensajeError = null;

  const EstadoSolicitudRecuperacion.enviando()
    : fase = FaseSolicitudRecuperacion.enviando,
      correo = null,
      tituloError = null,
      mensajeError = null;

  const EstadoSolicitudRecuperacion.enviado({required String this.correo})
    : fase = FaseSolicitudRecuperacion.enviado,
      tituloError = null,
      mensajeError = null;

  const EstadoSolicitudRecuperacion.error({
    required String this.tituloError,
    required String this.mensajeError,
  }) : fase = FaseSolicitudRecuperacion.error,
       correo = null;

  final FaseSolicitudRecuperacion fase;

  /// A dónde se envió el código. Solo en [FaseSolicitudRecuperacion.enviado],
  /// para pasárselo a la pantalla donde se escribe el código.
  final String? correo;

  final String? tituloError;
  final String? mensajeError;

  bool get enviando => fase == FaseSolicitudRecuperacion.enviando;
}
