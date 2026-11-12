import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/recorrido_local.dart';
import '../screens/sincronizacion/sincronizacion_screen.dart';
import '../services/sincronizacion_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// El indicador de pendientes de la portada (Desarrollo Móvil): cuántos
/// recorridos quedaron en el teléfono sin subir, y acceso a la pantalla de
/// sincronización.
///
/// Solo aparece cuando hay algo. Mientras carga, o si el teléfono no se pudo
/// leer, no se pinta: la portada no es el lugar para ese error, y la
/// pantalla de sincronización lo cuenta si se entra a ella.
class AvisoSincronizacion extends ConsumerWidget {
  const AvisoSincronizacion({super.key});

  static const clave = Key('aviso-sincronizacion');

  static String titulo(int cuantos) =>
      cuantos == 1 ? '1 recorrido sin subir' : '$cuantos recorridos sin subir';

  /// Si la base rechazó alguno, eso es lo que hay que decir: no se arregla
  /// solo, como lo demás.
  static String detalle(List<RecorridoLocal> recorridos) {
    final rechazados = recorridos.where((r) => r.rechazado).length;
    if (rechazados == 0) return 'Se suben solos con conexión. Toca para ver';
    return rechazados == 1
        ? 'La base no aceptó 1. Toca para ver qué hacer'
        : 'La base no aceptó $rechazados. Toca para ver qué hacer';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorridos = ref.watch(recorridosPorSubirProvider).valueOrNull;
    if (recorridos == null || recorridos.isEmpty) {
      return const SizedBox.shrink();
    }
    final hayRechazados = recorridos.any((r) => r.rechazado);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: TrazaCard(
        key: clave,
        // `push`: al cerrarla se vuelve a la portada.
        onTap: () => context.push(SincronizacionScreen.ruta),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: hayRechazados
                    ? AppColors.dangerTint
                    : AppColors.accentTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hayRechazados
                    ? Icons.cloud_off_rounded
                    : Icons.cloud_upload_outlined,
                size: 20,
                color: hayRechazados ? AppColors.danger : AppColors.accentInk,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo(recorridos.length),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle(recorridos),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}
