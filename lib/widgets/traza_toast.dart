import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Aviso breve al pie de la pantalla (`.toast` del prototipo).
///
/// Se apoya en el [ScaffoldMessenger] raíz de la app, así que el mensaje sigue
/// visible aunque justo después se cambie de pantalla.
void mostrarToast(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          24,
        ),
        duration: const Duration(milliseconds: 2400),
      ),
    );
}
