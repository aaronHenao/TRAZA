import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_login.dart';
import 'auth_service.dart';

/// Estado del botón de Google. Lo comparten login y registro: con Google no
/// hay diferencia entre registrarse e iniciar sesión.
final inicioGoogleProvider =
    NotifierProvider.autoDispose<InicioGoogleNotifier, EstadoLogin>(
      InicioGoogleNotifier.new,
    );

/// Inicia sesión con Google (SCRUM-68) y procesa el resultado: entró, canceló
/// o falló (SCRUM-69 y SCRUM-58).
class InicioGoogleNotifier extends AutoDisposeNotifier<EstadoLogin> {
  bool _activo = false;

  @override
  EstadoLogin build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    return const EstadoLogin.inicial();
  }

  Future<void> iniciar() async {
    if (state.enviando) return;

    final authService = ref.read(authServiceProvider);
    state = const EstadoLogin.enviando();

    try {
      final entro = await authService.iniciarSesionConGoogle();
      // Cerrar la ventana de Google no es un error: se vuelve al inicio sin
      // mostrar nada (criterio 5).
      _publicar(
        entro ? const EstadoLogin.exito() : const EstadoLogin.inicial(),
      );
    } on InicioSesionException catch (e) {
      _publicar(
        EstadoLogin.error(tituloError: e.titulo, mensajeError: e.mensaje),
      );
    } catch (e) {
      debugPrint('Error inesperado al iniciar sesión con Google: $e');
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
