import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_registro.dart';
import 'auth_service.dart';

/// Estado del formulario de registro.
///
/// `autoDispose`: se destruye cuando la pantalla de registro deja de
/// escucharlo. Así, si el usuario vuelve a registrarse después, arranca
/// limpio en vez de encontrar el éxito o el error anterior.
final registroProvider =
    NotifierProvider.autoDispose<RegistroNotifier, EstadoRegistro>(
      RegistroNotifier.new,
    );

/// Lógica del registro (SCRUM-50 y SCRUM-51), separada de la pantalla para
/// poder probarla sin widgets.
class RegistroNotifier extends AutoDisposeNotifier<EstadoRegistro> {
  /// Si el provider sigue vivo. Riverpod 2 no trae `ref.mounted`: evita
  /// publicar un estado cuando el usuario cerró la pantalla mientras se
  /// esperaba a Supabase.
  bool _activo = false;

  @override
  EstadoRegistro build() {
    _activo = true;
    ref.onDispose(() => _activo = false);
    return const EstadoRegistro.inicial();
  }

  Future<void> registrar({
    required String nombre,
    required String correo,
    required String password,
  }) async {
    // Evita un segundo envío si llega un doble toque.
    if (state.enviando) return;

    // Se lee antes del await: después, el provider podría estar destruido.
    final authService = ref.read(authServiceProvider);
    state = const EstadoRegistro.enviando();

    try {
      final requiereConfirmacion = await authService.registrar(
        nombre: nombre,
        correo: correo,
        password: password,
      );
      _publicar(
        EstadoRegistro.exito(
          correo: correo,
          requiereConfirmacion: requiereConfirmacion,
        ),
      );
    } on CorreoYaRegistradoException {
      _publicar(
        const EstadoRegistro.error(
          tituloError: 'Correo en uso',
          mensajeError: 'El correo ingresado ya está asociado a una cuenta',
        ),
      );
    } on RegistroException catch (e) {
      _publicar(
        EstadoRegistro.error(tituloError: e.titulo, mensajeError: e.mensaje),
      );
    } catch (e) {
      // Cualquier error que no venga de Supabase. Se imprime para depurarlo.
      debugPrint('Error inesperado al registrar: $e');
      _publicar(
        const EstadoRegistro.error(
          tituloError: 'Algo salió mal',
          mensajeError: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
        ),
      );
    }
  }

  void _publicar(EstadoRegistro nuevo) {
    if (_activo) state = nuevo;
  }
}
