import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Barra superior del prototipo (`.topbar`): botón opcional a la izquierda,
/// título centrado y un espacio equivalente a la derecha para que el título
/// quede realmente centrado.
class TrazaTopBar extends StatelessWidget {
  const TrazaTopBar({required this.titulo, this.onAtras, super.key});

  final String titulo;

  /// Si es null no se dibuja el botón de retroceso (pantallas de onboarding
  /// donde no se puede volver, como Perfil o Permisos).
  final VoidCallback? onAtras;

  static const _anchoBoton = 36.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, AppSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: _anchoBoton,
            child: onAtras == null
                ? null
                : TrazaIconButton(
                    icon: Icons.chevron_left,
                    onPressed: onAtras,
                    tooltip: 'Volver',
                  ),
          ),
          Expanded(
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.17,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: _anchoBoton),
        ],
      ),
    );
  }
}

/// Botón circular del prototipo (`.icon-btn`): 36x36, borde de 1px.
class TrazaIconButton extends StatelessWidget {
  const TrazaIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: AppColors.bg,
          shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
        ),
      ),
    );
  }
}
