import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/estado_solicitud_recuperacion.dart';
import '../../services/solicitud_recuperacion_provider.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_widgets.dart';

/// Primer paso de la recuperación: pedir el código al correo (SCRUM-73).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.correoInicial = ''});

  /// Correo que el usuario ya había escrito en el login.
  final String correoInicial;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _correoController = TextEditingController(
    text: widget.correoInicial,
  );

  @override
  void dispose() {
    _correoController.dispose();
    super.dispose();
  }

  void _onEnviarCodigo() {
    if (!_formKey.currentState!.validate()) return;

    ref
        .read(solicitudRecuperacionProvider.notifier)
        .solicitar(correo: _correoController.text.trim());
  }

  void _alCambiarSolicitud(
    EstadoSolicitudRecuperacion? anterior,
    EstadoSolicitudRecuperacion actual,
  ) {
    switch (actual.fase) {
      case FaseSolicitudRecuperacion.enviado:
        _mostrarEnviadoYContinuar(actual.correo!);
      case FaseSolicitudRecuperacion.error:
        _mostrarAlerta(actual.tituloError!, actual.mensajeError!);
      case FaseSolicitudRecuperacion.inicial ||
          FaseSolicitudRecuperacion.enviando:
        break;
    }
  }

  /// Mismo mensaje exista o no la cuenta (criterio 2 ajustado). Al cerrarlo,
  /// pasa a escribir el código.
  Future<void> _mostrarEnviadoYContinuar(String correo) async {
    await _mostrarAlerta(
      'Revisa tu correo',
      'Si $correo está registrado, te enviamos un código para recuperar tu '
          'contraseña.',
    );

    if (!mounted) return;
    // push y no go: desde el código, "Pedir otro" regresa aquí.
    context.push('/restablecer', extra: correo);
  }

  Future<void> _mostrarAlerta(String titulo, String mensaje) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(solicitudRecuperacionProvider, _alCambiarSolicitud);
    final enviando = ref.watch(solicitudRecuperacionProvider).enviando;

    return AuthLayout(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MarcaTraza(),
            const SizedBox(height: 36),
            const Text(
              'Recupera tu contraseña',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorTextoPrincipal,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Escribe tu correo y te enviaremos un código para crear una '
              'contraseña nueva.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colorTextoSecundario,
              ),
            ),
            const SizedBox(height: 28),

            const EtiquetaCampo('Correo electrónico'),
            TextFormField(
              controller: _correoController,
              validator: validarCorreo,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) {
                if (!enviando) _onEnviarCodigo();
              },
              decoration: const InputDecoration(hintText: 'nombre@correo.com'),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: enviando ? null : _onEnviarCodigo,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: enviando
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enviar código'),
            ),
            const SizedBox(height: 12),

            // En iPhone no hay botón atrás físico y esta pantalla no tiene barra
            // superior: sin este botón la persona quedaría atrapada.
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver a iniciar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
