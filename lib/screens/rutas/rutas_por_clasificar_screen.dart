import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/reloj_provider.dart';
import '../../services/rutas_provider.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_ruta.dart';
import '../../widgets/traza_top_bar.dart';
import 'detalle_ruta_screen.dart';

/// La bandeja del Runner Experto: las rutas que esperan su dificultad
/// (criterio 1 de SCRUM-363), la que lleva más tiempo esperando primero.
///
/// Tocar una abre su detalle, que es donde se ve el mapa y se asigna la
/// dificultad. Cualquier experto puede tomar cualquiera: la que clasifica
/// otro desaparece al volver.
class RutasPorClasificarScreen extends ConsumerWidget {
  const RutasPorClasificarScreen({super.key});

  static const ruta = '/rutas-por-clasificar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutas = ref.watch(rutasPorClasificarProvider);
    final ahora = ref.read(relojProvider)();

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: 'Rutas por clasificar',
                onAtras: context.canPop() ? context.pop : null,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(rutasPorClasificarProvider),
                  child: switch (rutas) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const EstadoVacio(
                        icono: Icons.task_alt_rounded,
                        titulo: 'No hay rutas por clasificar',
                        detalle:
                            'Cuando alguien publique una ruta, aparecerá aquí '
                            'para que le asignes la dificultad.',
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
                      itemBuilder: (context, i) => TarjetaRuta(
                        key: TarjetaRuta.claveDe(lista[i].id),
                        ruta: lista[i],
                        ahora: ahora,
                        onTap: () async {
                          // Con la ruta del listado, el detalle la muestra
                          // mientras llega su trazado (SCRUM-250).
                          await context.push(
                            DetalleRutaScreen.rutaDe(lista[i].id),
                            extra: lista[i],
                          );
                          if (!context.mounted) return;
                          ref.invalidate(rutasPorClasificarProvider);
                        },
                      ),
                    ),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_rounded,
                      titulo: 'No pudimos cargar las rutas',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(rutasPorClasificarProvider),
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
