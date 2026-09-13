import 'package:flutter/material.dart';

import '../../widgets/auth_widgets.dart';

/// Provisional: existe para que el login tenga a dónde llevar (SCRUM-65).
/// El formulario de recuperación llega con la HU SCRUM-36.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key, this.correoInicial = ''});

  /// Correo que el usuario ya había escrito en el login, para no pedirlo
  /// otra vez.
  final String correoInicial;

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
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
          Text(
            correoInicial.isEmpty
                ? 'Muy pronto podrás recuperar tu contraseña desde aquí.'
                : 'Muy pronto podrás recuperar la contraseña de $correoInicial '
                      'desde aquí.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 28),
          // En iPhone no hay botón atrás físico y esta pantalla no tiene barra
          // superior: sin este botón la persona quedaría atrapada.
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: const Text('Volver a iniciar sesión'),
          ),
        ],
      ),
    );
  }
}
