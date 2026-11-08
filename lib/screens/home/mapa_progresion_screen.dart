import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/mapa_progresion.dart';
import '../../services/mapa_progresion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/camino_progresion.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';
import '../rutas/detalle_ruta_screen.dart';

/// El mapa de progresión: el camino de rutas oficiales con el punto donde va
/// el corredor (rutas oficiales, etapa 2; antes, el de niveles de
/// SCRUM-226).
///
/// Es una sección de la barra inferior ("Progreso"), así que está a un toque
/// desde cualquier otra. Por eso no lleva botón de atrás. Solo consulta: las
/// rutas y su orden los elige el administrador, y qué rutas completó el
/// corredor lo registra la base. Los niveles y la XP siguen en Tu progresión.
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
    final siguiente = mapa.siguiente;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        if (!mapa.hayRutas)
          const _SinRutas()
        else ...[
          Text(
            mapa.caminoTerminado
                ? '¡Completaste el camino!'
                : 'Siguiente: ${siguiente!.ruta.nombre}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${mapa.totalCompletadas} de ${mapa.paradas.length} rutas '
            'completadas',
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
          const SizedBox(height: AppSpacing.md),
          TrazaCard(
            child: CaminoProgresion(
              mapa: mapa,
              // `push`: desde el detalle se vuelve al mapa. La ruta viaja
              // en `extra` para mostrar lo que ya se sabe mientras llega su
              // trazado, como desde Explorar.
              onTapRuta: (ruta) =>
                  context.push(DetalleRutaScreen.rutaDe(ruta.id), extra: ruta),
            ),
          ),
        ],
      ],
    );
  }
}

/// El administrador todavía no ha elegido rutas oficiales: no hay camino, y
/// se dice por qué.
class _SinRutas extends StatelessWidget {
  const _SinRutas();

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
                  'Todavía no hay rutas oficiales',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Cuando el administrador las elija, verás tu camino aquí.',
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

/// El detalle del error no le sirve al corredor; se avisa y se deja
/// reintentar.
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
