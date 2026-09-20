import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/historial_entrenamientos.dart';
import '../../models/resumen_entrenamiento.dart';
import '../../services/historial_service.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/traza_top_bar.dart';
import '../summary/resumen_screen.dart';

/// Historial de entrenamientos (`screen-history`, SCRUM-44).
///
/// Lista las sesiones finalizadas del usuario (SCRUM-123 y SCRUM-124) y al
/// tocar una abre su resumen (SCRUM-125).
class HistorialScreen extends ConsumerWidget {
  const HistorialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Como sección de la barra inferior no lleva flecha: se sale por la
    // barra. Abierto encima de otra pantalla (el "+" de un resumen, por
    // ejemplo) sí, para poder devolverse.
    final volver = context.canPop() ? context.pop : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            TrazaTopBar(titulo: 'Historial de entrenamientos', onAtras: volver),
            Expanded(
              // SCRUM-127: carga, error y datos.
              child: ref
                  .watch(historialProvider)
                  .when(
                    // Al reintentar también se ve el indicador de carga.
                    skipLoadingOnRefresh: false,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => _EstadoCentrado(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar tu historial',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () => ref.invalidate(historialProvider),
                        child: const Text('Reintentar'),
                      ),
                    ),
                    data: (entrenamientos) => entrenamientos.isEmpty
                        ? _EstadoCentrado(
                            icono: Icons.schedule,
                            titulo: 'Aún no tienes entrenamientos',
                            detalle:
                                'Cuando termines tu primer entrenamiento, '
                                'aparecerá aquí.',
                            accion: FilledButton(
                              onPressed: () => context.go('/actividad'),
                              child: const Text(
                                'Iniciar mi primer entrenamiento',
                              ),
                            ),
                          )
                        : _Lista(entrenamientos: entrenamientos),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.entrenamientos});

  final List<ResumenEntrenamiento> entrenamientos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.read(relojProvider)();

    // Deslizar hacia abajo vuelve a consultar.
    return RefreshIndicator(
      onRefresh: () => ref.refresh(historialProvider.future),
      child: ListView.separated(
        // `.history-wrap`.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          6,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        itemCount: entrenamientos.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.line),
        itemBuilder: (context, i) =>
            _Fila(entrenamiento: entrenamientos[i], ahora: ahora),
      ),
    );
  }
}

/// `.history-list-row`: icono de la actividad, actividad y fecha, distancia y
/// tiempo.
class _Fila extends StatelessWidget {
  const _Fila({required this.entrenamiento, required this.ahora});

  final ResumenEntrenamiento entrenamiento;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // SCRUM-125. push y `desde=historial`: la X del resumen vuelve aquí.
      onTap: () => context.push(
        '${ResumenScreen.rutaPara(entrenamiento.entrenamientoId)}'
        '?desde=historial',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.secondaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconoDe(entrenamiento.nombreActividad),
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
                    entrenamiento.subtitulo(ahora),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entrenamiento.detalleHistorial,
                    style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  /// Igual que `activityIcon` del prototipo: caminando o corriendo.
  static IconData _iconoDe(String actividad) =>
      actividad == 'Caminar' ? Icons.directions_walk : Icons.directions_run;
}

/// Icono en círculo gris, título, detalle y una acción, centrados
/// (`.history-empty`).
class _EstadoCentrado extends StatelessWidget {
  const _EstadoCentrado({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            accion,
          ],
        ),
      ),
    );
  }
}
