import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Tarjeta base del prototipo (`.card`).
///
/// Cuando [seleccionada] es true adopta el estado que el prototipo usa tanto en
/// `.goal-card.selected` como en `.permission-card.granted`: borde y fondo en
/// el color primario.
class TrazaCard extends StatelessWidget {
  const TrazaCard({
    required this.child,
    this.seleccionada = false,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final bool seleccionada;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borde = seleccionada ? AppColors.primary : AppColors.line;
    final fondo = seleccionada ? AppColors.primaryTint : AppColors.bg;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: borde),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadow.card,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
