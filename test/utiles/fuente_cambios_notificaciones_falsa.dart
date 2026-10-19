import 'dart:async';

import 'package:traza/services/cambios_notificaciones.dart';

/// Doble de `FuenteCambiosNotificaciones`: la prueba decide qué avisos llegan
/// y puede comprobar si alguien sigue escuchando.
class FuenteCambiosNotificacionesFalsa implements FuenteCambiosNotificaciones {
  late final _avisos =
      StreamController<(String, CambioNotificaciones)>.broadcast(
        onListen: () => escuchando = true,
        onCancel: () => escuchando = false,
      );

  bool escuchando = false;

  /// De quién se están escuchando los avisos.
  String? usuario;

  @override
  Stream<CambioNotificaciones> de(String usuarioId) {
    usuario = usuarioId;
    return _avisos.stream
        .where((evento) => evento.$1 == usuarioId)
        .map((evento) => evento.$2);
  }

  void emitir(
    String usuarioId, [
    CambioNotificaciones cambio = const CambioNotificaciones(
      TipoCambioNotificaciones.nueva,
    ),
  ]) => _avisos.add((usuarioId, cambio));
}
