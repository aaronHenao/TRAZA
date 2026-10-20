import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recompensa.dart';
import '../../services/recompensas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_recompensa.dart';
import '../../widgets/traza_top_bar.dart';

/// Las recompensas que administra el administrador (SCRUM-374): todas,
/// disponibles o no, y el botón para crear una nueva.
class GestionRecompensasScreen extends ConsumerWidget {
  const GestionRecompensasScreen({super.key});

  static const ruta = '/admin/recompensas';
  static const rutaNueva = '$ruta/nueva';

  static const claveBotonNueva = Key('admin-nueva-recompensa');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recompensas = ref.watch(gestionRecompensasProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: claveBotonNueva,
        // `push`: al volver del formulario se regresa aquí, y la lista se
        // refresca con la recompensa recién creada.
        onPressed: () async {
          await context.push(rutaNueva);
          ref.invalidate(gestionRecompensasProvider);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Nueva recompensa',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: 'Gestión de recompensas',
                // Se llega desde el panel del administrador; si se abrió la
                // ruta directamente no hay a dónde volver.
                onAtras: context.canPop() ? context.pop : null,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Text(
                  'Lo que los corredores pueden obtener con sus puntos',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(gestionRecompensasProvider),
                  child: switch (recompensas) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const EstadoVacio(
                        icono: Icons.card_giftcard_outlined,
                        titulo: 'Todavía no hay recompensas',
                        detalle:
                            'Crea la primera con el botón +. Las disponibles '
                            'aparecen en el catálogo de los corredores.',
                      ),
                    AsyncData(value: final lista) => _Lista(recompensas: lista),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar las recompensas',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(gestionRecompensasProvider),
                        child: const Text('Reintentar'),
                      ),
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.recompensas});

  final List<Recompensa> recompensas;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // Hueco al final para que el botón + no tape la última tarjeta.
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 96),
      itemCount: recompensas.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => TarjetaRecompensa(
        key: TarjetaRecompensa.claveDe(recompensas[i].id),
        recompensa: recompensas[i],
        conDisponibilidad: true,
      ),
    );
  }
}
