import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Sección para iniciar el entrenamiento: el bloque central `.home-center` y
/// el botón "Iniciar actividad" del prototipo.
class SeccionIniciarEntrenamiento extends StatelessWidget {
  const SeccionIniciarEntrenamiento({
    required this.actividad,
    required this.onIniciar,
    this.aviso,
    super.key,
  });

  /// Actividad elegida con los chips (SCRUM-92), o null si todavía no hay
  /// ninguna.
  final String? actividad;

  /// Arranca el entrenamiento; se conecta en SCRUM-96. Mientras sea null, o
  /// mientras no haya actividad, el botón queda deshabilitado.
  final VoidCallback? onIniciar;

  /// Explica debajo del botón por qué todavía no se puede iniciar, cuando es
  /// algo que el usuario puede resolver (por ejemplo, iniciar sesión).
  final String? aviso;

  @override
  Widget build(BuildContext context) {
    final actividad = this.actividad;
    final aviso = this.aviso;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryTint,
                  ),
                  child: const Icon(
                    Icons.play_circle_outline_rounded,
                    size: 38,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  actividad ?? 'Ninguna actividad seleccionada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: actividad == null ? AppColors.ink3 : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: const Text(
                    'Al iniciar verás el cronómetro, tu ubicación y la '
                    'distancia recorrida en tiempo real.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.ink2),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: actividad == null ? null : onIniciar,
          child: const Text('Iniciar actividad'),
        ),
        if (aviso != null) ...[
          const SizedBox(height: 10),
          Text(
            aviso,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.ink2,
            ),
          ),
        ],
      ],
    );
  }
}
