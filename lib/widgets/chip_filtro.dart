import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Chip para filtrar una lista: el elegido va en negro, los demás con borde.
///
/// Se usa en el catálogo del corredor, en la gestión del administrador y en
/// el historial de retos. Van en un `Wrap`, así que no se estiran: varios por
/// línea y saltan de línea cuando no caben.
class ChipFiltro extends StatelessWidget {
  const ChipFiltro({
    required this.texto,
    required this.activo,
    required this.onTap,
    super.key,
  });

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activo,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: activo ? AppColors.ink : AppColors.bg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: activo ? AppColors.ink : AppColors.line),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: activo ? AppColors.bg : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de chips centrada, que salta de línea cuando no caben.
class FilaChips extends StatelessWidget {
  const FilaChips({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      // Ancho completo: sin esto el Wrap mide lo que ocupan los chips y su
      // `alignment` no tiene espacio donde centrarlos, porque las columnas
      // que lo contienen alinean a la izquierda.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          // Centrados: pegados a un lado, la última línea de un salto queda
          // descolgada del resto.
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: children,
        ),
      ),
    );
  }
}
