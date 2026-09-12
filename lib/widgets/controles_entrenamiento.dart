import 'package:flutter/material.dart';

import '../theme/traza_theme.dart';

/// Botones de pausar y finalizar la actividad (SCRUM-102).
///
/// El widget no decide nada: solo avisa de los toques. Quien lo usa
/// decide si pausa el cronómetro, guarda el entrenamiento, etc.
class ControlesEntrenamiento extends StatelessWidget {
  const ControlesEntrenamiento({
    super.key,
    required this.pausado,
    required this.onPausar,
    required this.onFinalizar,
  });

  /// Cambia el icono entre pausa y reanudar.
  final bool pausado;

  final VoidCallback onPausar;
  final VoidCallback onFinalizar;

  static const Key clavePausar = Key('control-pausar');
  static const Key claveFinalizar = Key('control-finalizar');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 34),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _BotonLateral(
            key: clavePausar,
            icono: pausado ? Icons.play_arrow_rounded : Icons.pause_rounded,
            tooltip: pausado ? 'Reanudar actividad' : 'Pausar actividad',
            onPressed: onPausar,
          ),
          const SizedBox(width: 22),
          _BotonFinalizar(
            key: claveFinalizar,
            onPressed: onFinalizar,
          ),
        ],
      ),
    );
  }
}

/// `.side-btn` del prototipo: 56 px, fondo blanco al 10 %.
class _BotonLateral extends StatelessWidget {
  const _BotonLateral({
    super.key,
    required this.icono,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.1),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icono, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.rec-btn` del prototipo: 74 px, morado de marca con sombra.
class _BotonFinalizar extends StatelessWidget {
  const _BotonFinalizar({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Finalizar actividad',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: TrazaColors.primary.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: TrazaColors.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: const SizedBox(
              width: 74,
              height: 74,
              child: Icon(Icons.stop_rounded, size: 26, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
