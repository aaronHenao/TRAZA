import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/traza_top_bar.dart';

/// Marcador de posición de `screen-permissions`.
///
/// La pantalla real es SCRUM-76 (Aceptar permisos). Aquí solo existe el destino
/// de navegación que necesita el botón "Continuar" del perfil (SCRUM-86); quien
/// tome SCRUM-76 reemplaza el contenido de este archivo.
class PermisosScreen extends StatelessWidget {
  const PermisosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TrazaTopBar(
              titulo: 'Permisos',
              onAtras: Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null,
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    'Pantalla pendiente (SCRUM-76).',
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
