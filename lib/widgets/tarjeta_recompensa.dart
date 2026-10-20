import 'package:flutter/material.dart';

import '../models/recompensa.dart';
import '../theme/app_colors.dart';
import 'traza_card.dart';

/// Una recompensa con los puntos que cuesta (SCRUM-374).
///
/// La usan el catálogo del corredor y la gestión del administrador. Solo la
/// gestión pide [conDisponibilidad] y [acciones]: el corredor únicamente ve
/// lo que puede obtener.
class TarjetaRecompensa extends StatelessWidget {
  const TarjetaRecompensa({
    required this.recompensa,
    this.conDisponibilidad = false,
    this.acciones = const [],
    super.key,
  });

  final Recompensa recompensa;
  final bool conDisponibilidad;

  /// Botones al pie, en una fila: lo que el administrador puede hacer con
  /// la recompensa (SCRUM-380).
  final List<Widget> acciones;

  static Key claveDe(String id) => Key('recompensa-$id');

  /// "1 punto", "150 puntos". Sin separador de miles, como los km y la XP.
  static String textoPuntos(int puntos) =>
      puntos == 1 ? '1 punto' : '$puntos puntos';

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.secondaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.card_giftcard_outlined,
              size: 20,
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recompensa.nombre,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recompensa.descripcion,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  textoPuntos(recompensa.puntosRequeridos),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                if (conDisponibilidad) ...[
                  const SizedBox(height: 4),
                  Text(
                    recompensa.disponible ? 'Disponible' : 'No disponible',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: recompensa.disponible
                          ? AppColors.secondaryDark
                          : AppColors.ink3,
                    ),
                  ),
                ],
                if (acciones.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, children: acciones),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
