import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/periodicidad_reto.dart';
import '../../models/reto.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_reto.dart';
import '../../widgets/traza_top_bar.dart';

/// Catálogo de retos que el corredor puede intentar (SCRUM-164).
///
/// Muestra solo los vigentes hoy, agrupados por periodicidad como en el
/// prototipo. Activarlos es de SCRUM-136; aquí se ven y se abren.
class RetosScreen extends ConsumerWidget {
  const RetosScreen({super.key});

  static const claveHistorial = Key('retos-historial');

  /// `null` es la pestaña "Todos", que no filtra nada.
  static Key clavePestana(PeriodicidadReto? periodicidad) =>
      Key('reto-tab-${periodicidad?.valorDb ?? 'todas'}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retos = ref.watch(retosVigentesProvider);
    final periodicidad = ref.watch(filtroRetosCorredorProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Cabecera(),
              const _Pestanas(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(retosVigentesProvider),
                  child: switch (retos) {
                    AsyncData(value: final todos) => _Lista(
                      retos: periodicidad == null
                          ? todos
                          : todos
                                .where((r) => r.periodicidad == periodicidad)
                                .toList(),
                      hayFiltro: periodicidad != null,
                    ),
                    AsyncError() => _NoSePudoCargar(
                      onReintentar: () => ref.invalidate(retosVigentesProvider),
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

class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Retos',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.19,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Elige uno y gana XP al cumplirlo',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Historial de retos, como el botón de la topbar del prototipo.
          TrazaIconButton(
            key: RetosScreen.claveHistorial,
            icon: Icons.schedule,
            tooltip: 'Mis retos',
            onPressed: () => context.push('/retos/historial'),
          ),
        ],
      ),
    );
  }
}

/// Diario · Semanal · Mensual, como el `.segmented` del prototipo, más
/// "Todos" para no esconder nada por defecto.
class _Pestanas extends ConsumerWidget {
  const _Pestanas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(filtroRetosCorredorProvider);

    return FilaChips(
      children: [
        for (final opcion in <PeriodicidadReto?>[
          null,
          ...PeriodicidadReto.values,
        ])
          ChipFiltro(
            key: RetosScreen.clavePestana(opcion),
            texto: opcion?.etiqueta ?? 'Todos',
            activo: opcion == elegida,
            onTap: () =>
                ref.read(filtroRetosCorredorProvider.notifier).state = opcion,
          ),
      ],
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.retos, required this.hayFiltro});

  final List<Reto> retos;
  final bool hayFiltro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (retos.isEmpty) return _SinRetos(hayFiltro: hayFiltro);

    // El mismo día para toda la lista: si cada tarjeta leyera el reloj por su
    // cuenta, dos podrían contar días distintos al cruzar la medianoche.
    final hoy = ref.read(relojProvider)();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: retos.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final reto = retos[i];
        return TarjetaReto(
          key: TarjetaReto.claveDe(reto.id),
          reto: reto,
          hoy: hoy,
          // SCRUM-166: del listado al detalle.
          onTap: () => context.push('/retos/${reto.id}', extra: reto),
        );
      },
    );
  }
}

class _SinRetos extends StatelessWidget {
  const _SinRetos({required this.hayFiltro});

  final bool hayFiltro;

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      icono: hayFiltro ? Icons.filter_alt_outlined : Icons.flag_outlined,
      titulo: hayFiltro
          ? 'Ningún reto de este tipo'
          : 'No hay retos disponibles',
      detalle: hayFiltro
          ? 'Prueba con otra periodicidad.'
          : 'Vuelve más tarde: aquí aparecerán los retos vigentes.',
    );
  }
}

class _NoSePudoCargar extends StatelessWidget {
  const _NoSePudoCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      icono: Icons.cloud_off_outlined,
      titulo: 'No pudimos cargar los retos',
      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      accion: OutlinedButton(
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    );
  }
}
