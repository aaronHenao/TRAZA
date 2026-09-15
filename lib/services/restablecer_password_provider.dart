import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_restablecer_password.dart';
import 'auth_service.dart';

final restablecerPasswordProvider =
    NotifierProvider.autoDispose<
      RestablecerPasswordNotifier,
      EstadoRestablecerPassword
    >(RestablecerPasswordNotifier.new);

/// Verifica el código y cambia la contraseña (SCRUM-74).
class RestablecerPasswordNotifier
    extends AutoDisposeNotifier<EstadoRestablecerPassword> {
  bool _activo = false;

  /// El código se gasta al verificarlo. Si ya se verificó y lo que falló fue
  /// la contraseña, el siguiente intento no vuelve a verificarlo.
  bool _codigoVerificado = false;

  @override
  EstadoRestablecerPassword build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    return const EstadoRestablecerPassword.inicial();
  }

  Future<void> restablecer({
    required String correo,
    required String codigo,
    required String nuevaPassword,
  }) async {
    if (state.enviando) return;

    final authService = ref.read(authServiceProvider);
    state = const EstadoRestablecerPassword.enviando();

    try {
      if (!_codigoVerificado) {
        await authService.verificarCodigoRecuperacion(
          correo: correo,
          codigo: codigo,
        );
        _codigoVerificado = true;
      }

      await authService.cambiarPassword(nuevaPassword: nuevaPassword);
      _publicar(const EstadoRestablecerPassword.exito());
    } on RecuperacionException catch (e) {
      _publicar(
        EstadoRestablecerPassword.error(
          tituloError: e.titulo,
          mensajeError: e.mensaje,
        ),
      );
    } catch (e) {
      debugPrint('Error inesperado al restablecer la contraseña: $e');
      _publicar(
        const EstadoRestablecerPassword.error(
          tituloError: 'Algo salió mal',
          mensajeError: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      );
    }
  }

  void _publicar(EstadoRestablecerPassword nuevo) {
    if (_activo) state = nuevo;
  }
}
