import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/explorar_rutas_provider.dart';
import '../../services/permisos_provider.dart';
import '../../services/ubicacion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/navegacion_principal.dart';
import '../../widgets/tarjeta_ruta_explorar.dart';
import '../../widgets/traza_top_bar.dart';

/// Explorar rutas: la sección de Rutas de la barra inferior (SCRUM-246).
///
/// Lista las rutas de la comunidad de la más cercana a la más lejana
/// (criterio 1 de HU-29). Si no se sabe dónde está el usuario —sin permiso,
/// con la ubicación apagada o sin respuesta del GPS—, muestra las más
/// recientes y lo dice en el rótulo, para que la sección no se quede vacía.
///
/// Cada ruta va en una [TarjetaRutaExplorar] (SCRUM-247), la misma del
/// carrusel de la portada, así una ruta se reconoce igual en los dos sitios.
class RutasScreen extends ConsumerWidget {
  const RutasScreen({super.key});

  static const ruta = '/rutas';

  static const titulo = 'Explorar rutas';

  static const claveLista = Key('rutas-lista');
  static const claveOrden = Key('rutas-orden');
  static const claveReintentar = Key('rutas-reintentar');

  /// Lo que dice el rótulo según cómo se ordenó la lista.
  static const rotuloCercania = 'CERCA DE TI';
  static const rotuloRecientes = 'LAS MÁS RECIENTES';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const NavegacionPrincipal(
      seccion: SeccionPrincipal.rutas,
      child: SafeArea(
        bottom: false,
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(titulo: titulo),
              Expanded(child: _Contenido()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido();

  Future<void> _recargar(WidgetRef ref) async {
    // El permiso se vuelve a consultar porque el usuario pudo concederlo en
    // los ajustes del teléfono, y la ubicación se vuelve a leer porque pudo
    // moverse.
    await ref.read(permisosProvider.notifier).actualizar();
    ref.invalidate(ubicacionActualProvider);
    try {
      // Se espera la lista nueva para que el indicador no se vaya antes de
      // tiempo. Si falla, la pantalla ya lo muestra: aquí no hay nada más
      // que hacer con el error.
      await ref.read(rutasParaExplorarProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mientras no se sepa qué decidió el usuario sobre la ubicación, la
    // lista saldría por recientes y un instante después se reordenaría por
    // cercanía: mejor esperar ese instante que hacer saltar la pantalla.
    final consultado = ref.watch(permisosProvider.select((p) => p.consultado));
    if (!consultado) return const Center(child: CircularProgressIndicator());

    final rutas = ref.watch(rutasParaExplorarProvider);

    return RefreshIndicator(
      onRefresh: () => _recargar(ref),
      child: switch (rutas) {
        // Reintentando tras un error: se ve que está cargando, no el error
        // de antes.
        AsyncError() when rutas.isLoading => const Center(
          child: CircularProgressIndicator(),
        ),
        AsyncError() => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No pudimos cargar las rutas',
          detalle: 'Revisa tu conexión e inténtalo de nuevo.',
          accion: OutlinedButton(
            key: RutasScreen.claveReintentar,
            onPressed: () => ref.invalidate(rutasParaExplorarProvider),
            child: const Text('Reintentar'),
          ),
        ),
        // Con datos, o recargando con los de antes: la lista no desaparece
        // mientras se actualiza.
        AsyncValue(valueOrNull: final datos?) => _Lista(datos: datos),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.datos});

  final RutasParaExplorar datos;

  @override
  Widget build(BuildContext context) {
    final rutas = datos.rutas;

    if (rutas.isEmpty) {
      return const EstadoVacio(
        icono: Icons.map_outlined,
        titulo: 'Todavía no hay rutas para mostrarte',
        detalle:
            'Cuando la comunidad publique rutas, las vas a encontrar en esta '
            'lista.',
      );
    }

    return ListView.separated(
      key: RutasScreen.claveLista,
      // Sin esto, con pocas rutas la lista no responde al gesto de recargar.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      // La primera fila es el rótulo que dice cómo va ordenada.
      itemCount: rutas.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) => i == 0
          ? _Orden(porCercania: datos is RutasPorCercania)
          : TarjetaRutaExplorar(
              key: TarjetaRutaExplorar.claveDe(rutas[i - 1].id),
              ruta: rutas[i - 1],
            ),
    );
  }
}

/// Cómo va ordenada la lista. Sin esto, el orden por cercanía no se nota:
/// las tarjetas dicen cuánto mide cada ruta, no a cuánto queda.
class _Orden extends StatelessWidget {
  const _Orden({required this.porCercania});

  final bool porCercania;

  @override
  Widget build(BuildContext context) {
    return Text(
      porCercania ? RutasScreen.rotuloCercania : RutasScreen.rotuloRecientes,
      key: RutasScreen.claveOrden,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.52,
        color: AppColors.ink2,
      ),
    );
  }
}
