import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/widgets/traza_top_bar.dart';
import 'actividad_providers.dart';
import 'widgets/chips_tipo_actividad.dart';
import 'widgets/seccion_iniciar_entrenamiento.dart';

/// Pantalla de inicio (`screen-home` del prototipo): el usuario elige su
/// actividad y arranca el entrenamiento.
///
/// La estructura es de SCRUM-91, los chips con la actividad elegida de
/// SCRUM-92 y la configuración de inicio de SCRUM-93. Falta a propósito la
/// acción de "Iniciar actividad", que se conecta en SCRUM-96 y hoy se pasa en
/// null.
class InicioScreen extends ConsumerWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actividad = ref.watch(actividadSeleccionadaProvider);
    final configuracion = ref.watch(configuracionInicioProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          // `.home-wrap` del prototipo.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Cabecera(),
              const SizedBox(height: 24),
              const ChipsTipoActividad(),
              const SizedBox(height: 24),
              Expanded(
                child: SeccionIniciarEntrenamiento(
                  actividad: actividad?.nombre,
                  onIniciar: null,
                  // Hay actividad elegida, pero viene del catálogo local
                  // porque no hay sesión: sin id no se puede crear el
                  // entrenamiento (ver ConfiguracionInicio.para).
                  aviso: actividad != null && configuracion == null
                      ? 'Inicia sesión para empezar a entrenar.'
                      : null,
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
