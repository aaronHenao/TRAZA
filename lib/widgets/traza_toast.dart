import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Aviso breve al pie de la pantalla (`.toast` del prototipo).
///
/// Se apoya en el [ScaffoldMessenger] raíz de la app, así que el mensaje sigue
/// visible aunque justo después se cambie de pantalla.
///
/// [separacionInferior] sube el aviso cuando al pie hay botones que no debe
/// tapar.
void mostrarToast(
  BuildContext context,
  String mensaje, {
  double separacionInferior = 24,
}) {
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
        margin: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          separacionInferior,
        ),
        duration: const Duration(milliseconds: 2400),
      ),
    );
}
