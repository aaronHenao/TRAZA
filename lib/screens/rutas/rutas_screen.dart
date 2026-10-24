import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../models/ruta.dart';
import '../../services/busqueda_rutas_provider.dart';
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
///
/// Arriba va una barra que busca por nombre o por quien creó la ruta
/// (SCRUM-254, HU-30). Con lo escrito, la lista muestra lo que coincide,
/// con las mismas tarjetas; sin nada escrito, vuelven las cercanas.
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
  static const claveBusqueda = Key('rutas-busqueda');
  static const claveResultados = Key('rutas-resultados');
  static const claveSinResultados = Key('rutas-sin-resultados');
  static const claveBuscando = Key('rutas-buscando');

  /// Lo que dice el campo de búsqueda vacío.
  static const pistaBusqueda = 'Busca por nombre o creador';

  /// Lo que dice el rótulo según cómo se ordenó la lista.
  static const rotuloCercania = 'CERCA DE TI';
  static const rotuloRecientes = 'LAS MÁS RECIENTES';

  /// El rótulo cuando la lista muestra lo que encontró una búsqueda.
  static const rotuloResultados = 'RESULTADOS';

  /// Una búsqueda que no encontró nada (SCRUM-254).
  static const sinResultados = 'No encontramos rutas';

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
              _BarraBusqueda(),
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

  /// Con una búsqueda escrita, deslizar hacia abajo la repite: pudo
  /// publicarse algo que coincide.
  Future<void> _recargarBusqueda(WidgetRef ref) async {
    ref.invalidate(busquedaRutasProvider);
    try {
      await ref.read(busquedaRutasProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mientras no se sepa qué decidió el usuario sobre la ubicación, la
    // lista saldría por recientes y un instante después se reordenaría por
    // cercanía: mejor esperar ese instante que hacer saltar la pantalla.
    final consultado = ref.watch(permisosProvider.select((p) => p.consultado));
    if (!consultado) return const Center(child: CircularProgressIndicator());

    // La lista de siempre se sigue pidiendo aunque haya una búsqueda: al
    // borrarla, las cercanas vuelven al instante, sin consultarlas otra vez.
    final rutas = ref.watch(rutasParaExplorarProvider);
    final termino = ref.watch(
      textoBusquedaRutasProvider.select(terminoDeBusqueda),
    );

    return RefreshIndicator(
      onRefresh: () =>
          termino == null ? _recargar(ref) : _recargarBusqueda(ref),
      child: termino != null
          ? _Resultados(termino: termino)
          : switch (rutas) {
              // Reintentando tras un error: se ve que está cargando, no el
              // error de antes.
              AsyncError() when rutas.isLoading => const Center(
                child: CircularProgressIndicator(),
              ),
              AsyncError(:final error) => _Error(
                error: error,
                onReintentar: () => ref.invalidate(rutasParaExplorarProvider),
              ),
              // Con datos, o recargando con los de antes: la lista no
              // desaparece mientras se actualiza.
              AsyncValue(valueOrNull: final datos?) => _Lista(datos: datos),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }
}

/// Lo que encontró la búsqueda (SCRUM-254): en la misma lista y con la
/// misma tarjeta que las cercanas, que es lo que el usuario ya sabe leer.
class _Resultados extends ConsumerWidget {
  const _Resultados({required this.termino});

  /// Lo que se buscó, como lo recibió la base.
  final String termino;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busqueda = ref.watch(busquedaRutasProvider);

    return switch (busqueda) {
      AsyncError() when busqueda.isLoading => const Center(
        child: CircularProgressIndicator(),
      ),
      AsyncError(:final error) => _Error(
        error: error,
        onReintentar: () => ref.invalidate(busquedaRutasProvider),
      ),
      // Mientras llega lo de la última letra se quedan los resultados de
      // antes, con un indicador junto al rótulo: la lista no parpadea con
      // cada letra.
      AsyncValue(valueOrNull: final rutas?) when rutas.isNotEmpty =>
        _ListaDeRutas(
          clave: RutasScreen.claveResultados,
          encabezado: [
            _Rotulo(RutasScreen.rotuloResultados, cargando: busqueda.isLoading),
          ],
          rutas: rutas,
        ),
      // Vacío y sin nada en camino: de verdad no hay coincidencias.
      AsyncValue(valueOrNull: _?) when !busqueda.isLoading => EstadoVacio(
        key: RutasScreen.claveSinResultados,
        icono: Icons.search_off_rounded,
        titulo: RutasScreen.sinResultados,
        detalle: 'Ninguna ruta publicada coincide con «$termino».',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// La consulta falló (SCRUM-249).
///
/// Si la base respondió —con un error o con datos que no se entienden—, el
/// problema es de este lado y no sirve revisar el internet. Cualquier otra
/// cosa es que no llegó a responder: la conexión. Los dos ofrecen
/// reintentar, y deslizar hacia abajo también vuelve a consultar.
class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onReintentar});

  final Object error;

  /// Lo que se vuelve a pedir: las cercanas o la búsqueda (SCRUM-254).
  final VoidCallback onReintentar;

  /// `PostgrestException` es la base contestando con un error, y
  /// `FormatException`, una fila que no encaja con lo que la app espera.
  static bool _falloDeLaBase(Object error) =>
      error is PostgrestException || error is FormatException;

  @override
  Widget build(BuildContext context) {
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
        onPressed: onReintentar,
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
    final encabezado = [
      ?aviso,
      _Rotulo(
        datos is RutasPorCercania
            ? RutasScreen.rotuloCercania
            : RutasScreen.rotuloRecientes,
      ),
    ];

    return _ListaDeRutas(
      clave: RutasScreen.claveLista,
      encabezado: encabezado,
      rutas: rutas,
    );
  }
}

/// Rutas en tarjetas, con lo que va encima de ellas.
///
/// La comparten las cercanas y los resultados de una búsqueda (SCRUM-254):
/// mismas tarjetas, mismo espaciado y mismo toque para abrir el detalle.
class _ListaDeRutas extends StatelessWidget {
  const _ListaDeRutas({
    required this.clave,
    required this.encabezado,
    required this.rutas,
  });

  /// Distinta para cada lista: al pasar de una a otra se empieza arriba.
  final Key clave;
  final List<Widget> encabezado;
  final List<Ruta> rutas;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: clave,
      // Sin esto, con pocas rutas la lista no responde al gesto de recargar.
      physics: const AlwaysScrollableScrollPhysics(),
      // Al deslizar se esconde el teclado de la búsqueda, que si no tapa
      // media pantalla de resultados.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

/// El campo para buscar rutas por su nombre o por quien la creó
/// (SCRUM-254).
///
/// Va fijo debajo del título y no dentro de la lista: así sigue a mano
/// mientras se recorren los resultados.
class _BarraBusqueda extends ConsumerWidget {
  const _BarraBusqueda();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: TextField(
        key: RutasScreen.claveBusqueda,
        onChanged: (texto) =>
            ref.read(textoBusquedaRutasProvider.notifier).state = texto,
        textInputAction: TextInputAction.search,
        // Nombres de lugares y de personas: el corrector los cambiaría por
        // palabras del diccionario.
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: RutasScreen.pistaBusqueda,
          prefixIcon: Icon(Icons.search_rounded, color: AppColors.ink3),
        ),
      ),
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

/// El rótulo encima de las tarjetas: cómo va ordenada la lista, o que son
/// los resultados de una búsqueda (SCRUM-254). Sin esto, el orden por
/// cercanía no se nota: las tarjetas dicen cuánto mide cada ruta, no a
/// cuánto queda.
class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto, {this.cargando = false});

  final String texto;

  /// Vienen resultados nuevos mientras se ven los anteriores.
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            texto,
            key: RutasScreen.claveOrden,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.52,
              color: AppColors.ink2,
            ),
          ),
        ),
        if (cargando) ...[
          const SizedBox(width: AppSpacing.sm),
          const SizedBox.square(
            key: RutasScreen.claveBuscando,
            dimension: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Buscando',
            ),
          ),
        ],
      ],
    );
  }
}
