import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// Un aviso en tarjeta: un icono, qué pasa, qué hacer y un botón para
/// hacerlo.
///
/// Es solo el dibujo. Lo usan el aviso del permiso de ubicación
/// (`AvisoPermisoUbicacion`, SCRUM-248) y el de la ubicación apagada o sin
/// respuesta de Explorar rutas (SCRUM-249), para que los avisos de un mismo
/// tema se vean iguales en toda la app.
class TarjetaAviso extends StatelessWidget {
  const TarjetaAviso({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.etiquetaBoton,
    required this.onBoton,
    this.claveBoton,
    super.key,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final String etiquetaBoton;

  /// Null deja el botón desactivado, por ejemplo mientras ya se está
  /// haciendo lo que pide.
  final VoidCallback? onBoton;

  final Key? claveBoton;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.secondaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, size: 20, color: AppColors.secondaryDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      texto,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: claveBoton,
            onPressed: onBoton,
            child: Text(etiquetaBoton),
          ),
        ],
      ),
    );
  }
}
