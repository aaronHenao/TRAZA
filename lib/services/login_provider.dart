import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_login.dart';
import 'auth_service.dart';

/// Estado del formulario de inicio de sesión. `autoDispose`: al salir de la
/// pantalla se destruye, y volver a ella arranca limpio.
final loginProvider = NotifierProvider.autoDispose<LoginNotifier, EstadoLogin>(
  LoginNotifier.new,
);

/// Lógica del inicio de sesión (SCRUM-64), separada de la pantalla para poder
/// probarla sin widgets.
class LoginNotifier extends AutoDisposeNotifier<EstadoLogin> {
  /// Si el provider sigue vivo. Evita publicar un estado cuando el usuario
  /// cerró la pantalla mientras se esperaba a Supabase.
  bool _activo = false;

  @override
  EstadoLogin build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    return const EstadoLogin.inicial();
  }

  Future<void> iniciarSesion({
    required String correo,
    required String password,
  }) async {
    // Evita un segundo envío si llega un doble toque.
    if (state.enviando) return;

    // Se lee antes del await: después, el provider podría estar destruido.
    final authService = ref.read(authServiceProvider);
    state = const EstadoLogin.enviando();

    try {
      await authService.iniciarSesion(correo: correo, password: password);
      _publicar(
        EstadoLogin.exito(requiereOnboarding: authService.requiereOnboarding),
      );
    } on CredencialesInvalidasException {
      _publicar(const EstadoLogin.credencialesInvalidas());
    } on InicioSesionException catch (e) {
      _publicar(
        EstadoLogin.error(tituloError: e.titulo, mensajeError: e.mensaje),
      );
    } catch (e) {
      // Cualquier error que no venga de Supabase. Se imprime para depurarlo.
      debugPrint('Error inesperado al iniciar sesión: $e');
      _publicar(
        const EstadoLogin.error(
          tituloError: 'Algo salió mal',
          mensajeError: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      );
    }
  }

  void _publicar(EstadoLogin nuevo) {
    if (_activo) state = nuevo;
  }
}
