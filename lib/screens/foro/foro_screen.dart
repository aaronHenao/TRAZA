import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/publicacion_foro.dart';
import '../../services/foro_provider.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_publicacion.dart';
import 'nueva_publicacion_screen.dart';

/// El foro de la comunidad (SCRUM-346): lo que publican los corredores, de lo
/// más reciente a lo más antiguo, con su autor y su fecha.
class ForoScreen extends ConsumerWidget {
  const ForoScreen({super.key});

  static const ruta = '/foro';

  static const claveNueva = Key('foro-nueva-publicacion');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicaciones = ref.watch(publicacionesForoProvider);

    void recargar() => ref.invalidate(publicacionesForoProvider);

    Future<void> nueva() async {
      // `push`: al volver, el foro se consulta de nuevo y la publicación
      // recién creada aparece arriba (criterio 1 de SCRUM-323).
      await context.push(NuevaPublicacionScreen.ruta);
      recargar();
    }

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cabecera(onNueva: nueva),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (publicaciones) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      EstadoVacio(
                        icono: Icons.forum_outlined,
                        titulo: 'Aún no hay publicaciones',
                        detalle:
                            'Abre la conversación: pregunta o comparte algo '
                            'sobre running.',
                        accion: OutlinedButton(
                          onPressed: nueva,
                          child: const Text('Publicar'),
                        ),
                      ),
                    AsyncData(value: final lista) => _Lista(
                      publicaciones: lista,
                    ),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar el foro',
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

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.onNueva});

  final VoidCallback onNueva;

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
                  'Foro',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.19,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Pregunta, comparte y aprende de la comunidad',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            key: ForoScreen.claveNueva,
            onPressed: onNueva,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Publicar'),
          ),
        ],
      ),
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.publicaciones});

  final List<PublicacionForo> publicaciones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.read(relojProvider)();

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: publicaciones.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final publicacion = publicaciones[i];
        return TarjetaPublicacion(
          key: TarjetaPublicacion.claveDe(publicacion.id),
          publicacion: publicacion,
          ahora: ahora,
        );
      },
    );
  }
}
