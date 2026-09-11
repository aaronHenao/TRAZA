import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/widgets/traza_top_bar.dart';
import 'widgets/seccion_iniciar_entrenamiento.dart';

/// Pantalla de inicio (`screen-home` del prototipo): el usuario elige su
/// actividad y arranca el entrenamiento.
///
/// SCRUM-91 arma la estructura. Faltan, a propósito:
/// - los chips de tipo de actividad, que llegan en SCRUM-92 entre la cabecera
///   y la sección de inicio;
/// - la actividad elegida (SCRUM-92) y la acción de "Iniciar actividad"
///   (SCRUM-96), que hoy se pasan en null.
class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Padding(
          // `.home-wrap` del prototipo.
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cabecera(),
              SizedBox(height: 24),
              Expanded(
                child: SeccionIniciarEntrenamiento(
                  actividad: null,
                  onIniciar: null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saludo y acceso al historial (`.home-head` del prototipo).
class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Listo para entrenar',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.19,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Elige tu actividad y comienza',
                style: TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
            ],
          ),
        ),
        // Lleva al historial de entrenamientos (SCRUM-44). Queda deshabilitado
        // hasta que exista esa pantalla.
        TrazaIconButton(
          icon: Icons.schedule,
          onPressed: null,
          tooltip: 'Historial',
        ),
      ],
    );
  }
}
