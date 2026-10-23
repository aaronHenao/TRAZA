import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../services/explorar_rutas_provider.dart';
import '../../services/permisos_provider.dart';
import '../../services/ubicacion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/aviso_permiso_ubicacion.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/navegacion_principal.dart';
import '../../widgets/tarjeta_aviso.dart';
import '../../widgets/tarjeta_ruta_explorar.dart';
import '../../widgets/traza_top_bar.dart';
import '../../widgets/traza_toast.dart';
import 'detalle_ruta_screen.dart';

/// Explorar rutas: la sección de Rutas de la barra inferior (SCRUM-246).
///
/// Lista las rutas de la comunidad de la más cercana a la más lejana
/// (criterio 1 de HU-29). Si no se sabe dónde está el usuario —sin permiso,
/// con la ubicación apagada o sin respuesta del GPS—, muestra las más
/// recientes y lo dice en el rótulo, para que la sección no se quede vacía.
///
/// Arriba de esas recientes va siempre por qué no van por cercanía y qué
/// hacer: conceder el permiso ([AvisoPermisoUbicacion], SCRUM-248), o
/// encender la ubicación o esperar al GPS e intentarlo otra vez (SCRUM-249).
///
/// Cuando no hay nada que mostrar se dice por qué (SCRUM-249, criterio 4 de
/// HU-29): no es lo mismo que no haya rutas cerca que no haya ninguna
/// publicada todavía. Y si la consulta falla, se distingue un problema de
/// conexión, que el usuario puede revisar, de uno de la base, que no.
///
/// Cada ruta va en una [TarjetaRutaExplorar] (SCRUM-247), la misma del
/// carrusel de la portada, así una ruta se reconoce igual en los dos sitios.
/// Tocarla abre su detalle ([DetalleRutaScreen], SCRUM-250, criterio 5 de
/// HU-29).
class RutasScreen extends ConsumerWidget {
  const RutasScreen({super.key});

  static const ruta = '/rutas';

  static const titulo = 'Explorar rutas';

  static const claveLista = Key('rutas-lista');
  static const claveOrden = Key('rutas-orden');
  static const claveReintentar = Key('rutas-reintentar');
  static const claveError = Key('rutas-error');
  static const claveSinRutasCerca = Key('rutas-sin-rutas-cerca');
  static const claveSinRutas = Key('rutas-sin-rutas');
  static const claveAvisoUbicacion = Key('rutas-aviso-ubicacion');
  static const claveReintentarUbicacion = Key('rutas-reintentar-ubicacion');

  /// Lo que dice el rótulo según cómo se ordenó la lista.
  static const rotuloCercania = 'CERCA DE TI';
  static const rotuloRecientes = 'LAS MÁS RECIENTES';

  /// Sin rutas a menos del radio de cercanía (criterio 4 de HU-29).
  static const sinRutasCerca = 'No encontramos rutas cerca de ti';

  /// Sin ninguna ruta publicada en toda la comunidad.
  static const sinRutas = 'Todavía no hay rutas publicadas';

  static const errorTitulo = 'No pudimos cargar las rutas';
  static const errorDeConexion =
      'Revisa tu conexión a internet e inténtalo de nuevo.';
  static const errorDeLaBase =
      'Algo falló de nuestro lado. Inténtalo de nuevo en un momento.';

  static const ubicacionApagada = 'Tu ubicación está apagada';
  static const ubicacionSinRespuesta = 'No pudimos ubicarte';

  /// Lo que se dice si al reintentar todavía no se sabe dónde está.
  static const todaviaSinUbicacion = 'Todavía no podemos ubicarte.';

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
        AsyncError(:final error) => _Error(error: error),
        // Con datos, o recargando con los de antes: la lista no desaparece
        // mientras se actualiza.
        AsyncValue(valueOrNull: final datos?) => _Lista(datos: datos),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// La consulta falló (SCRUM-249).
///
/// Si la base respondió —con un error o con datos que no se entienden—, el
/// problema es de este lado y no sirve revisar el internet. Cualquier otra
/// cosa es que no llegó a responder: la conexión. Los dos ofrecen
/// reintentar, y deslizar hacia abajo también vuelve a consultar.
class _Error extends ConsumerWidget {
  const _Error({required this.error});

  final Object error;

  /// `PostgrestException` es la base contestando con un error, y
  /// `FormatException`, una fila que no encaja con lo que la app espera.
  static bool _falloDeLaBase(Object error) =>
      error is PostgrestException || error is FormatException;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deLaBase = _falloDeLaBase(error);

    return EstadoVacio(
      key: RutasScreen.claveError,
      icono: deLaBase ? Icons.error_outline : Icons.cloud_off_outlined,
      titulo: RutasScreen.errorTitulo,
      detalle: deLaBase
          ? RutasScreen.errorDeLaBase
          : RutasScreen.errorDeConexion,
      accion: OutlinedButton(
        key: RutasScreen.claveReintentar,
        onPressed: () => ref.invalidate(rutasParaExplorarProvider),
        child: const Text('Reintentar'),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.datos});

  final RutasParaExplorar datos;

  @override
  Widget build(BuildContext context) {
    final rutas = datos.rutas;

    // Sin nada que mostrar se dice por qué, en vez de dejar la lista en
    // blanco (criterio 4 de HU-29): no es lo mismo que no haya rutas cerca
    // que no haya ninguna todavía.
    if (rutas.isEmpty) {
      return switch (datos) {
        RutasPorCercania() => EstadoVacio(
          key: RutasScreen.claveSinRutasCerca,
          icono: Icons.explore_off_outlined,
          titulo: RutasScreen.sinRutasCerca,
          detalle:
              'No hay rutas publicadas a menos de '
              '${radioRutasCercanasKm.round()} km de donde estás. Cuando '
              'alguien publique una por aquí, la vas a ver en esta lista.',
        ),
        RutasRecientes() => const EstadoVacio(
          key: RutasScreen.claveSinRutas,
          icono: Icons.route_outlined,
          titulo: RutasScreen.sinRutas,
          // La misma invitación del apartado de rutas del foro.
          detalle:
              'Cuando termines un entrenamiento, publica su recorrido desde '
              'el resumen para que la comunidad pueda seguirlo.',
        ),
      };
    }

    // Si no van por cercanía, arriba se dice por qué y qué hacer: conceder
    // el permiso, o encender la ubicación o esperar al GPS. Al resolverlo,
    // la lista se vuelve a pedir sola —la ubicación depende de eso— y el
    // aviso se va.
    final aviso = switch (datos) {
      RutasRecientes(motivo: UbicacionSinPermiso()) =>
        const AvisoPermisoUbicacion(),
      RutasRecientes(motivo: UbicacionApagada()) => const _AvisoUbicacion(
        apagada: true,
      ),
      RutasRecientes(motivo: UbicacionNoSePudo()) => const _AvisoUbicacion(
        apagada: false,
      ),
      _ => null,
    };

    // Lo que va antes de las rutas: el aviso, si hace falta, y el rótulo que
    // dice cómo va ordenada.
    final encabezado = [?aviso, _Orden(porCercania: datos is RutasPorCercania)];

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
      itemCount: encabezado.length + rutas.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        if (i < encabezado.length) return encabezado[i];
        final ruta = rutas[i - encabezado.length];
        return TarjetaRutaExplorar(
          key: TarjetaRutaExplorar.claveDe(ruta.id),
          ruta: ruta,
          // Criterio 5 de HU-29 (SCRUM-250). Con `push`, al cerrar el detalle
          // se vuelve a la lista donde estaba, sin consultarla otra vez. La
          // ruta va en `extra` para que el detalle muestre lo que ya se sabe
          // de ella mientras llega su trazado.
          onTap: () =>
              context.push(DetalleRutaScreen.rutaDe(ruta.id), extra: ruta),
        );
      },
    );
  }
}

/// La ubicación del teléfono está apagada, o el GPS no respondió a tiempo
/// (SCRUM-249).
///
/// El permiso sí está, así que no es el aviso del permiso: aquí lo que toca
/// es encenderla, o acercarse a una ventana si se está bajo techo, y volver
/// a intentarlo.
class _AvisoUbicacion extends ConsumerWidget {
  const _AvisoUbicacion({required this.apagada});

  final bool apagada;

  Future<void> _reintentar(BuildContext context, WidgetRef ref) async {
    ref.invalidate(ubicacionActualProvider);
    final ubicacion = await ref.read(ubicacionActualProvider.future);
    // Si se ubicó, la lista pasa a ir por cercanía y este aviso desaparece.
    // Si no, se dice: sin esto, el botón parecería no hacer nada.
    if (ubicacion is! UbicacionConocida && context.mounted) {
      mostrarToast(context, RutasScreen.todaviaSinUbicacion);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TarjetaAviso(
      key: RutasScreen.claveAvisoUbicacion,
      icono: apagada
          ? Icons.location_disabled_outlined
          : Icons.gps_off_outlined,
      titulo: apagada
          ? RutasScreen.ubicacionApagada
          : RutasScreen.ubicacionSinRespuesta,
      texto: apagada
          ? 'Enciéndela en el teléfono para ver las rutas que tienes cerca.'
          : 'El GPS no respondió a tiempo. Si estás bajo techo, acércate a '
                'una ventana e inténtalo de nuevo.',
      etiquetaBoton: 'Reintentar',
      claveBoton: RutasScreen.claveReintentarUbicacion,
      onBoton: () => _reintentar(context, ref),
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
