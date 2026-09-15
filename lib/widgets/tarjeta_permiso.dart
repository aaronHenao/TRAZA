import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// Tarjeta que explica un permiso y deja concederlo (`.permission-card` del
/// prototipo).
///
/// Cuando [concedido] es true se pinta en el color primario y el botón se
/// cambia por la etiqueta "Permiso concedido".
class TarjetaPermiso extends StatelessWidget {
  const TarjetaPermiso({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.textoBoton,
    required this.onPermitir,
    required this.onAhoraNo,
    this.concedido = false,
    super.key,
  });

  final IconData icono;
  final String titulo;

  /// Para qué funciones de la app se necesita el permiso.
  final String descripcion;
  final String textoBoton;
  final VoidCallback? onPermitir;
  final VoidCallback onAhoraNo;
  final bool concedido;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      seleccionada: concedido,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: concedido
                      ? AppColors.primary
                      : AppColors.secondaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icono,
                  size: 20,
                  color: concedido ? Colors.white : AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descripcion,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink2,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Wrap y no Row: con letra grande o pantalla angosta, "Ahora no"
          // baja de línea en lugar de desbordarse.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (concedido)
                const _EtiquetaConcedido()
              else
                OutlinedButton(
                  onPressed: onPermitir,
                  // `.btn-sm`: más bajo que el botón normal del tema.
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(textoBoton),
                ),
              if (!concedido)
                TextButton(
                  onPressed: onAhoraNo,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ink3,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Ahora no'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EtiquetaConcedido extends StatelessWidget {
  const _EtiquetaConcedido();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 16, color: AppColors.primaryDark),
        SizedBox(width: 6),
        Text(
          'Permiso concedido',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
      ],
    );
  }
}
