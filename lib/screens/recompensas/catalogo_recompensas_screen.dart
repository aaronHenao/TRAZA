import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/recompensas_provider.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_recompensa.dart';
import '../../widgets/traza_top_bar.dart';

/// El catálogo de recompensas del corredor (criterio 3 de SCRUM-374): las
/// disponibles, cada una con los puntos que cuesta, de la más barata a la
/// más cara.
class CatalogoRecompensasScreen extends ConsumerWidget {
  const CatalogoRecompensasScreen({super.key});

  static const ruta = '/recompensas';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoRecompensasProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: 'Recompensas',
                // Se abre con `push` desde la portada; si se llegó por la
                // dirección no hay a dónde volver.
                onAtras: context.canPop() ? context.pop : null,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(catalogoRecompensasProvider),
                  child: switch (catalogo) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const EstadoVacio(
                        icono: Icons.card_giftcard_outlined,
                        titulo: 'Todavía no hay recompensas',
                        detalle:
                            'Cuando haya beneficios para canjear con tus '
                            'puntos, aparecerán aquí.',
                      ),
                    AsyncData(value: final lista) => ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      itemCount: lista.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) => TarjetaRecompensa(
                        key: TarjetaRecompensa.claveDe(lista[i].id),
                        recompensa: lista[i],
                      ),
                    ),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar las recompensas',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(catalogoRecompensasProvider),
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
