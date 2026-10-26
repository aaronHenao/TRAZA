import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Pastilla con las pestañas de una pantalla: la abierta va en blanco sobre el
/// fondo gris, igual que el selector de la gestión de retos.
///
/// Las pestañas se reparten el ancho por partes iguales, así que sirve para
/// dos o tres. Para más opciones, y para filtros que se combinan, están los
/// chips de `ChipFiltro`, que saltan de línea cuando no caben.
///
/// La gestión de retos tiene su propia copia de esta pastilla, anterior a este
/// widget; puede migrar aquí cuando alguien toque esa pantalla.
class PestanasSegmentadas extends StatelessWidget {
  const PestanasSegmentadas({required this.children, super.key});

  /// Las pestañas, normalmente [PestanaSegmentada].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.bgAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          children: [for (final pestana in children) Expanded(child: pestana)],
        ),
      ),
    );
  }
}

/// Una pestaña dentro de [PestanasSegmentadas].
class PestanaSegmentada extends StatelessWidget {
  const PestanaSegmentada({
    required this.texto,
    required this.abierta,
    required this.onTap,
    super.key,
  });

  final String texto;
  final bool abierta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: abierta,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: abierta ? AppColors.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: abierta ? AppShadow.card : null,
          ),
          // En la pantalla más estrecha una etiqueta larga partiría en dos
          // líneas y movería la pastilla: se encoge antes que partirse.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              texto,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: abierta ? AppColors.ink : AppColors.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
