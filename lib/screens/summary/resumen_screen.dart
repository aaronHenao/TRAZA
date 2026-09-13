import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/traza_top_bar.dart';

/// Marcador de posición de `screen-summary`.
///
/// La pantalla real es SCRUM-117 (Diseñar la pantalla de resumen del
/// entrenamiento). Aquí solo existe el destino de navegación que necesita el
/// cierre de la actividad (SCRUM-121); SCRUM-117 reemplaza el contenido de este
/// archivo.
class ResumenScreen extends StatelessWidget {
  const ResumenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TrazaTopBar(titulo: 'Resumen'),
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    'Pantalla pendiente (SCRUM-117).',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.ink2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
