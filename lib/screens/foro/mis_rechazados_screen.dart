import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/foro_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_moderacion.dart';
import '../../widgets/traza_top_bar.dart';

/// Lo que la moderación le rechazó al usuario (SCRUM-322 / SCRUM-339):
/// publicaciones, comentarios y ediciones, con el motivo, quién lo rechazó y
/// cuándo. Arriba, cuántas faltas lleva (SCRUM-338).
///
/// Abrirla marca los rechazos como vistos: el contador del foro vuelve a
/// cero.
class MisRechazadosScreen extends ConsumerStatefulWidget {
  const MisRechazadosScreen({super.key});

  static const ruta = '/foro/rechazados';

  static const claveFaltas = Key('mis-rechazados-faltas');

  static String textoFaltas(int faltas) => faltas == 1
      ? 'Llevas 1 falta en el foro'
      : 'Llevas $faltas faltas en el foro';

  @override
  ConsumerState<MisRechazadosScreen> createState() =>
      _MisRechazadosScreenState();
}

class _MisRechazadosScreenState extends ConsumerState<MisRechazadosScreen> {
  @override
  void initState() {
    super.initState();
    // Después del primer cuadro: `ref` todavía no deja invalidar providers
    // mientras se construye.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) marcarRechazosVistos(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(foroEnVivoProvider);
    final rechazados = ref.watch(misRechazadosProvider);

    void recargar() => ref.invalidate(misModeracionesProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Mis rechazados', onAtras: context.pop),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (rechazados) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const EstadoVacio(
                        icono: Icons.verified_outlined,
                        titulo: 'No tienes nada rechazado',
                        detalle:
                            'Si la moderación retira algo que publiques, '
                            'aquí verás el motivo.',
                      ),
                    AsyncData(value: final lista) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      children: [
                        _Faltas(faltas: lista.length),
                        const SizedBox(height: AppSpacing.md),
                        for (final m in lista) ...[
                          TarjetaModeracion(moderacion: m),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    ),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar tus rechazados',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: recargar,
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

/// El historial de faltas, resumido (SCRUM-338).
class _Faltas extends StatelessWidget {
  const _Faltas({required this.faltas});

  final int faltas;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: MisRechazadosScreen.claveFaltas,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MisRechazadosScreen.textoFaltas(faltas),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Cada contenido rechazado por spam o por incumplir las normas de '
            'la comunidad cuenta como una falta.',
            style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
          ),
        ],
      ),
    );
  }
}
