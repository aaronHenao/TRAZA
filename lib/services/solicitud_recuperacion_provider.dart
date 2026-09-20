import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_solicitud_recuperacion.dart';
import 'auth_service.dart';

final solicitudRecuperacionProvider =
    NotifierProvider.autoDispose<
      SolicitudRecuperacionNotifier,
      EstadoSolicitudRecuperacion
    >(SolicitudRecuperacionNotifier.new);

/// Pide el código de recuperación (SCRUM-73).
class SolicitudRecuperacionNotifier
    extends AutoDisposeNotifier<EstadoSolicitudRecuperacion> {
  bool _activo = false;

  @override
  EstadoSolicitudRecuperacion build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    return const EstadoSolicitudRecuperacion.inicial();
  }

  Future<void> solicitar({required String correo}) async {
    if (state.enviando) return;

    final authService = ref.read(authServiceProvider);
    state = const EstadoSolicitudRecuperacion.enviando();

    try {
      await authService.solicitarRecuperacion(correo: correo);
      _publicar(EstadoSolicitudRecuperacion.enviado(correo: correo));
    } on RecuperacionException catch (e) {
      _publicar(
        EstadoSolicitudRecuperacion.error(
          tituloError: e.titulo,
          mensajeError: e.mensaje,
        ),
      );
    } catch (e) {
      debugPrint('Error inesperado al solicitar recuperación: $e');
      _publicar(
        const EstadoSolicitudRecuperacion.error(
          tituloError: 'Algo salió mal',
          mensajeError: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      );
    }
  }

  void _publicar(EstadoSolicitudRecuperacion nuevo) {
    if (_activo) state = nuevo;
  }
}
