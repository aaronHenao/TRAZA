import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/estado_restablecer_password.dart';
import '../../services/restablecer_password_provider.dart';
import '../../utils/validators.dart';
import '../../widgets/auth_widgets.dart';
import 'login_screen.dart';

/// Segundo paso de la recuperación: código y nueva contraseña (SCRUM-74).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.correo});

  /// Correo al que se envió el código. Supabase lo necesita para verificarlo.
  final String correo;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmacionController = TextEditingController();

  bool _verPassword = false;

  @override
  void dispose() {
    _codigoController.dispose();
    _passwordController.dispose();
    _confirmacionController.dispose();
    super.dispose();
  }

  void _onCambiarPassword() {
    if (!_formKey.currentState!.validate()) return;

    ref
        .read(restablecerPasswordProvider.notifier)
        .restablecer(
          correo: widget.correo,
          codigo: _codigoController.text.trim(),
          nuevaPassword: _passwordController.text,
        );
  }

  void _alCambiarEstado(
    EstadoRestablecerPassword? anterior,
    EstadoRestablecerPassword actual,
  ) {
    switch (actual.fase) {
      case FaseRestablecerPassword.exito:
        _mostrarExitoYVolverAlLogin();
      case FaseRestablecerPassword.error:
        _mostrarAlerta(actual.tituloError!, actual.mensajeError!);
      case FaseRestablecerPassword.inicial || FaseRestablecerPassword.enviando:
        break;
    }
  }

  Future<void> _mostrarExitoYVolverAlLogin() async {
    await _mostrarAlerta(
      'Contraseña actualizada',
      'Ya puedes iniciar sesión con tu nueva contraseña.',
    );

    if (!mounted) return;
    // Borra toda la pila y deja solo el login: atrás no vuelve al código.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
    ref.listen(restablecerPasswordProvider, _alCambiarEstado);
    final enviando = ref.watch(restablecerPasswordProvider).enviando;

    final ojito = IconButton(
      icon: Icon(
        _verPassword
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        color: colorTextoSecundario,
      ),
      onPressed: () => setState(() => _verPassword = !_verPassword),
    );

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
              'Crea una contraseña nueva',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: colorTextoPrincipal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escribe el código que enviamos a ${widget.correo} y elige tu '
              'nueva contraseña.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colorTextoSecundario,
              ),
            ),
            const SizedBox(height: 28),

            const EtiquetaCampo('Código de 6 dígitos'),
            TextFormField(
              controller: _codigoController,
              validator: validarCodigoRecuperacion,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(hintText: '123456'),
            ),
            const SizedBox(height: 18),

            const EtiquetaCampo('Nueva contraseña'),
            TextFormField(
              controller: _passwordController,
              validator: validarPassword,
              obscureText: !_verPassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                hintText: 'Crea una contraseña',
                suffixIcon: ojito,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder(
              valueListenable: _passwordController,
              builder: (context, valor, _) =>
                  ChecklistPassword(password: valor.text),
            ),
            const SizedBox(height: 18),

            const EtiquetaCampo('Confirmar contraseña'),
            TextFormField(
              controller: _confirmacionController,
              // Criterio 5: compara con lo que hay en el otro campo.
              validator: (valor) =>
                  validarConfirmacionPassword(valor, _passwordController.text),
              obscureText: !_verPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!enviando) _onCambiarPassword();
              },
              decoration: InputDecoration(
                hintText: 'Repite la contraseña',
                suffixIcon: ojito,
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: enviando ? null : _onCambiarPassword,
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
                  : const Text('Cambiar contraseña'),
            ),
            const SizedBox(height: 12),

            // Vuelve a la pantalla anterior, donde se puede pedir otro código.
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('¿No te llegó el código? Pedir otro'),
            ),
          ],
        ),
      ),
    );
  }
}
