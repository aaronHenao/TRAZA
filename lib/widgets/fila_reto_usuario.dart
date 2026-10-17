import 'package:flutter/material.dart';

import '../models/reto_del_usuario.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'tarjeta_reto.dart';
import 'traza_card.dart';

/// Un reto que el corredor tiene o tuvo, con su progreso hacia la meta.
///
/// La usan el historial (SCRUM-173) y la sección "En curso" del catálogo
/// (SCRUM-170): es la misma fila, y verla distinta en cada sitio haría dudar
/// de si habla del mismo reto.
class FilaRetoUsuario extends StatelessWidget {
  const FilaRetoUsuario({
    required this.reto,
    required this.ahora,
    this.onTap,
    super.key,
  });

  final RetoDelUsuario reto;
  final DateTime ahora;

  /// Abre el detalle. Nulo en el historial: de lo vencido y lo completado ya
  /// no hay nada que decidir.
  final VoidCallback? onTap;

  static Key claveDe(String retoId) => Key('mi-reto-$retoId');

  @override
  Widget build(BuildContext context) {
    final vencido = reto.vencidoEn(ahora);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TrazaCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Marca(reto: reto, vencido: vencido),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    reto.reto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: vencido ? AppColors.ink2 : AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InsigniaReto(
                  texto:
                      '${reto.completado ? '+' : ''}'
                      '${reto.reto.xpOtorgada} XP',
                  fondo: reto.completado
                      ? AppColors.primaryTint
                      : AppColors.bgAlt,
                  color: reto.completado
                      ? AppColors.primaryDark
                      : AppColors.ink3,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // El progreso importa sobre todo en lo vencido: saber que quedó
            // en 12 de 15 km es distinto de no haber empezado.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: reto.progreso,
                minHeight: 6,
                backgroundColor: AppColors.bgAlt,
                valueColor: AlwaysStoppedAnimation(
                  reto.completado
                      ? AppColors.primary
                      : vencido
                      ? AppColors.ink3
                      : AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${TarjetaReto.textoKm(reto.progresoKm)} de '
              '${TarjetaReto.textoKm(reto.reto.metaKm)} km',
              style: const TextStyle(fontSize: 12, color: AppColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.reto, required this.vencido});

  final RetoDelUsuario reto;
  final bool vencido;

  @override
  Widget build(BuildContext context) {
    final (icono, fondo, color) = reto.completado
        ? (Icons.check, AppColors.accentTint, AppColors.accentInk)
        : vencido
        ? (Icons.close, AppColors.bgAlt, AppColors.ink3)
        : (
            Icons.directions_run,
            AppColors.secondaryTint,
            AppColors.secondaryDark,
          );

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icono, size: 18, color: color),
    );
  }
}
