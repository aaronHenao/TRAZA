import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/foro_provider.dart';
import '../foro/detalle_publicacion_screen.dart';
import '../foro/nueva_publicacion_screen.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_publicacion.dart';
import '../../widgets/traza_top_bar.dart';

/// Lo que el administrador ve del foro (SCRUM-323): todas las publicaciones,
/// separadas entre las que están a la vista y las que retuvo la moderación.
///
/// Desde aquí el administrador también publica (SCRUM-354). Aprobar o
/// eliminar llega con SCRUM-322 y SCRUM-242, y la retención la hará la IA,
/// que todavía no existe.
class ModeracionForoScreen extends ConsumerWidget {
  const ModeracionForoScreen({super.key});

  static const ruta = '/admin/foro';

  static const claveNueva = Key('moderacion-nueva-publicacion');

  static Key claveVista(VistaModeracionForo vista) =>
      Key('moderacion-${vista.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todas = ref.watch(moderacionForoProvider);
    final filtradas = ref.watch(moderacionForoFiltradaProvider);
    final vista = ref.watch(vistaModeracionForoProvider);
    final ahora = ref.read(relojProvider)();

    void recargar() => ref.invalidate(moderacionForoProvider);

    Future<void> nueva() async {
      await context.push(NuevaPublicacionScreen.rutaAdmin);
      recargar();
    }

    int cuantas(VistaModeracionForo opcion) => switch (todas) {
      AsyncData(value: final lista) =>
        lista.where((p) => p.estado == opcion.estado).length,
      _ => 0,
    };

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: 'Moderación del foro',
                onAtras: context.pop,
                accion: TrazaIconButton(
                  key: claveNueva,
                  icon: Icons.edit_outlined,
                  tooltip: 'Nueva publicación',
                  onPressed: nueva,
                ),
              ),
              FilaChips(
                children: [
                  for (final opcion in VistaModeracionForo.values)
                    ChipFiltro(
                      key: claveVista(opcion),
                      texto: '${opcion.etiqueta} (${cuantas(opcion)})',
                      activo: opcion == vista,
                      onTap: () =>
                          ref.read(vistaModeracionForoProvider.notifier).state =
                              opcion,
                    ),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (filtradas) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      switch (vista) {
                        VistaModeracionForo.publicadas => const EstadoVacio(
                          icono: Icons.forum_outlined,
                          titulo: 'Nadie ha publicado todavía',
                          detalle:
                              'Aquí verás lo que los corredores publiquen en '
                              'el foro.',
                        ),
                        // Honesto mientras no haya IA: que la lista esté
                        // vacía no significa que alguien la esté revisando.
                        VistaModeracionForo.retenidas => const EstadoVacio(
                          icono: Icons.shield_outlined,
                          titulo: 'No hay publicaciones retenidas',
                          detalle:
                              'La moderación automática todavía no está '
                              'activa. Cuando lo esté, aquí aparecerá lo que '
                              'retenga, con su motivo.',
                        ),
                      },
                    AsyncData(value: final lista) => ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      itemCount: lista.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) => TarjetaPublicacion(
                        key: TarjetaPublicacion.claveDe(lista[i].id),
                        publicacion: lista[i],
                        ahora: ahora,
                        conEstado: true,
                        onTap: () => context.push(
                          DetallePublicacionScreen.rutaAdminDe(lista[i].id),
                        ),
                      ),
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
