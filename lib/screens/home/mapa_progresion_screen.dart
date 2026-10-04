import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mapa_progresion.dart';
import '../../services/mapa_progresion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/camino_progresion.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// El mapa de progresión (SCRUM-226): el camino de niveles con el punto donde
/// va el corredor.
///
/// Es una sección de la barra inferior ("Progreso"), así que está a un toque
/// desde cualquier otra (criterio 4). Por eso no lleva botón de atrás. Solo
/// consulta: la XP la asigna el motor de experiencia y los niveles los define
/// el administrador.
class MapaProgresionScreen extends ConsumerWidget {
  const MapaProgresionScreen({super.key});

  static const ruta = '/progreso';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapa = ref.watch(mapaProgresionProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TrazaTopBar(titulo: 'Mapa de progresión'),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(mapaProgresionProvider),
                  child: switch (mapa) {
                    AsyncData(value: final datos) => _Mapa(mapa: datos),
                    AsyncError() => _NoSePudoCargar(
                      onReintentar: () =>
                          ref.invalidate(mapaProgresionProvider),
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

class _Mapa extends StatelessWidget {
  const _Mapa({required this.mapa});

  final MapaProgresion mapa;

  @override
  Widget build(BuildContext context) {
    final parada = mapa.paradas[mapa.indiceActual];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Text(
          // En el inicio no se repite su nombre: ya lo dice el camino.
          parada.esInicio
              ? 'En el punto de partida'
              : 'Vas en ${parada.nombre}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${mapa.experiencia} XP acumulados',
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
        if (!mapa.hayNiveles) ...[
          const SizedBox(height: AppSpacing.md),
          const _SinNiveles(),
        ],
        const SizedBox(height: AppSpacing.md),
        TrazaCard(child: CaminoProgresion(mapa: mapa)),
      ],
    );
  }
}

/// El administrador todavía no ha creado niveles: el camino es solo el punto
/// de partida, y se dice por qué.
class _SinNiveles extends StatelessWidget {
  const _SinNiveles();

  @override
  Widget build(BuildContext context) {
    return const TrazaCard(
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 22, color: AppColors.ink3),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Todavía no hay niveles',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Cuando se configuren, verás tu camino aquí.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Criterio 5: el detalle del error no le sirve al corredor; se avisa y se
/// deja reintentar.
class _NoSePudoCargar extends StatelessWidget {
  const _NoSePudoCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      icono: Icons.cloud_off_outlined,
      titulo: 'No pudimos cargar tu mapa de progresión',
      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      accion: OutlinedButton(
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    );
  }
}
