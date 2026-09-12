import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/traza_card.dart';
import '../../domain/tipo_objetivo.dart';

/// Tarjeta seleccionable de un objetivo (`.goal-card` del prototipo).
class ObjetivoCard extends StatelessWidget {
  const ObjetivoCard({
    required this.tipo,
    required this.seleccionada,
    required this.onTap,
    this.configuracion,
    super.key,
  });

  final TipoObjetivo tipo;
  final bool seleccionada;
  final VoidCallback onTap;

  /// Fila para configurar el valor del objetivo. Se dibuja solo cuando la
  /// tarjeta está seleccionada.
  final Widget? configuracion;

  @override
  Widget build(BuildContext context) {
    final mostrarConfiguracion = seleccionada && configuracion != null;

    return TrazaCard(
      seleccionada: seleccionada,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tipo.etiqueta,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tipo.descripcion,
                      style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _MarcaSeleccion(seleccionada: seleccionada),
            ],
          ),
          if (mostrarConfiguracion) ...[
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Divider(color: AppColors.line, height: 1),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: configuracion,
            ),
          ],
        ],
      ),
    );
  }
}

/// Círculo con check del prototipo (`.goal-check`).
class _MarcaSeleccion extends StatelessWidget {
  const _MarcaSeleccion({required this.seleccionada});

  final bool seleccionada;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: seleccionada,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: seleccionada ? AppColors.primary : Colors.transparent,
          border: Border.all(
            color: seleccionada ? AppColors.primary : AppColors.line,
            width: 2,
          ),
        ),
        child: seleccionada
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
