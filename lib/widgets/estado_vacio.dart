import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Mensaje centrado para cuando una lista no tiene nada que mostrar: sin
/// datos, sin resultados para el filtro, o con la consulta fallida.
///
/// Va sobre un scroll aunque no haya nada que desplazar, para que "deslizar
/// para refrescar" siga funcionando justo cuando más falta hace. Y se centra
/// en el alto disponible en vez de quedarse pegado arriba, que es donde se
/// mira cuando la pantalla está vacía.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
    super.key,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  /// Botón opcional, como "Reintentar".
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) => ListView(
        // Sin esto, un ListView que no desborda no responde al gesto.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: restricciones.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.bgAlt,
                      ),
                      child: Icon(icono, size: 30, color: AppColors.ink3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      titulo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detalle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink2,
                        height: 1.4,
                      ),
                    ),
                    if (accion != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      accion!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
