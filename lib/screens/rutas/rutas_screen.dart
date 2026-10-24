import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../models/rango_distancia.dart';
import '../../models/ruta.dart';
import '../../models/zona.dart';
import '../../services/busqueda_rutas_provider.dart';
import '../../services/filtros_rutas_provider.dart';
import '../../services/explorar_rutas_provider.dart';
import '../../services/permisos_provider.dart';
import '../../services/ubicacion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/texto_para_buscar.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/aviso_permiso_ubicacion.dart';
import '../../widgets/chip_filtro.dart';
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
/// con las mismas tarjetas; sin nada escrito, vuelven las cercanas. Debajo
/// van los rangos de distancia (SCRUM-273, HU-37): con uno elegido, la
/// lista —las cercanas o los resultados— muestra solo las rutas que miden
/// eso (SCRUM-274).
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
  static const claveNotaZona = Key('rutas-nota-zona');
  static const claveSinZona = Key('rutas-sin-zona');
  static const claveBuscarComoLugar = Key('rutas-buscar-como-lugar');
  static const claveReintentarZona = Key('rutas-reintentar-zona');
  static const claveFiltroDistancia = Key('rutas-filtro-distancia');
  static const claveSinRutasEnRango = Key('rutas-sin-rutas-en-rango');
  static const claveQuitarFiltro = Key('rutas-quitar-filtro');

  /// El chip de un rango de distancia (SCRUM-273).
  static Key claveRango(RangoDistancia rango) =>
      Key('rutas-rango-${rango.name}');

  /// Lo que dice el campo de búsqueda vacío.
  static const pistaBusqueda = 'Busca por nombre, zona o creador';

  /// De dónde salen los lugares (SCRUM-255): los datos de OpenStreetMap
  /// piden decirlo donde se usan.
  static const atribucionZonas = 'Lugares: © colaboradores de OpenStreetMap';

  /// Lo que dice el rótulo según cómo se ordenó la lista.
  static const rotuloCercania = 'CERCA DE TI';
  static const rotuloRecientes = 'LAS MÁS RECIENTES';

  /// El rótulo cuando la lista muestra lo que encontró una búsqueda.
  static const rotuloResultados = 'RESULTADOS';

  /// Una búsqueda que no encontró nada (SCRUM-254).
  static const sinResultados = 'No encontramos rutas';

  /// Lo que se sugiere sin resultados (SCRUM-257, criterio 4 de HU-30).
  static const revisaLoEscrito =
      'Revisa cómo lo escribiste: basta con el comienzo del nombre de una '
      'ruta o de quien la publicó.';
  static const revisaLoEscritoVariasPalabras =
      'Revisa cómo lo escribiste o prueba con menos palabras: todas tienen '
      'que estar en el nombre de la ruta o en el de quien la publicó.';
  static const buscaloComoLugar = 'Si es un lugar, búscalo como lugar.';
  static const revisaLaConexion = 'Revisa tu conexión e inténtalo de nuevo.';

  /// Sin rutas a menos del radio de cercanía (criterio 4 de HU-29).
  static const sinRutasCerca = 'No encontramos rutas cerca de ti';

  /// Sin ninguna ruta publicada en toda la comunidad.
  static const sinRutas = 'Todavía no hay rutas publicadas';

  /// Ninguna ruta de la lista mide lo del rango elegido (SCRUM-274).
  static String sinRutasEnRango(RangoDistancia rango) =>
      'Ninguna ruta de ${rango.etiqueta.toLowerCase()}';
  static const pruebaOtroRango =
      'Prueba con otro rango o quita el filtro para verlas todas.';

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
              _FiltroDistancia(),
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
  /// publicarse algo que coincide. El lugar se vuelve a pedir por si la vez
  /// anterior no se pudo; si ya se tenía, sale guardado, sin salir a la red.
  Future<void> _recargarBusqueda(WidgetRef ref) async {
    ref
      ..invalidate(zonaBuscadaProvider)
      ..invalidate(busquedaRutasProvider);
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
///
/// Confirmada, suma las rutas que arrancan en el lugar que nombra lo
/// escrito, y dice cuál lugar encontró (SCRUM-255): sin eso, una ruta lejana
/// en la lista no tendría explicación, y "Belén" podría ser Boyacá sin que
/// el usuario lo supiera.
class _Resultados extends ConsumerWidget {
  const _Resultados({required this.termino});

  /// Lo que se buscó, como lo recibió la base.
  final String termino;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busqueda = ref.watch(busquedaRutasProvider);
    final confirmada = ref.watch(busquedaEstaConfirmadaProvider);
    final zona = ref.watch(zonaBuscadaProvider);

    // Lo que se sabe del lugar. Nada antes de confirmar: hasta entonces no
    // se pregunta.
    final lugar = confirmada ? zona.valueOrNull : null;
    final lugarNoDisponible = confirmada && zona.hasError && !zona.isLoading;

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
            if (lugar != null)
              _NotaZona(zona: lugar)
            else if (lugarNoDisponible)
              _NotaSinZona(termino: termino),
          ],
          rutas: rutas,
        ),
      // Vacío y sin nada en camino: de verdad no hay coincidencias. Sale
      // cuando el usuario termina de escribir, no con cada letra: antes se
      // ven los resultados de antes o el indicador.
      AsyncValue(valueOrNull: _?) when !busqueda.isLoading => _SinResultados(
        termino: termino,
        confirmada: confirmada,
        lugar: lugar,
        lugarNoDisponible: lugarNoDisponible,
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// La búsqueda no encontró ninguna ruta (SCRUM-257, criterio 4 de HU-30).
///
/// Dice que no hay resultados y sugiere revisar lo escrito, con lo que de
/// verdad hace fallar una búsqueda: cada palabra tiene que ser el comienzo
/// de una del nombre de la ruta o de quien la publicó (0041), así que una
/// letra cambiada o una palabra de más dejan la lista vacía.
///
/// Aparece sin que el usuario toque nada, cuando termina de escribir, así
/// que también se le anuncia al lector de pantalla: quien no ve la
/// pantalla no tendría cómo saber que la lista quedó vacía.
class _SinResultados extends ConsumerStatefulWidget {
  const _SinResultados({
    required this.termino,
    required this.confirmada,
    required this.lugar,
    required this.lugarNoDisponible,
  });

  final String termino;
  final bool confirmada;

  /// El lugar que nombra lo escrito, si se confirmó y se encontró.
  final Zona? lugar;

  /// Se confirmó, pero no se pudo preguntar por el lugar.
  final bool lugarNoDisponible;

  /// Qué no se encontró y qué hacer.
  String get detalle {
    final buscado = 'Ninguna ruta publicada coincide con «$termino»';
    final lugar = this.lugar;
    final queNo = switch ((confirmada, lugar, lugarNoDisponible)) {
      (true, final lugar?, _) =>
        '$buscado ni arranca en ${lugar.nombreCompleto}.',
      (true, null, true) => '$buscado, y no pudimos buscarlo como lugar.',
      (true, null, false) =>
        '$buscado, y no encontramos un lugar con ese nombre.',
      (false, _, _) => '$buscado.',
    };

    // Sin poder preguntar por el lugar, lo que hay que revisar es la
    // conexión, no lo escrito.
    if (lugarNoDisponible) {
      return '$queNo ${RutasScreen.revisaLaConexion}';
    }

    final variasPalabras = textoParaBuscar(termino).contains(' ');
    final sugerencia = variasPalabras
        ? RutasScreen.revisaLoEscritoVariasPalabras
        : RutasScreen.revisaLoEscrito;
    final comoLugar = confirmada ? '' : ' ${RutasScreen.buscaloComoLugar}';
    return '$queNo $sugerencia$comoLugar';
  }

  @override
  ConsumerState<_SinResultados> createState() => _SinResultadosState();
}

class _SinResultadosState extends ConsumerState<_SinResultados> {
  @override
  void initState() {
    super.initState();
    _anunciarDespuesDelCuadro();
  }

  @override
  void didUpdateWidget(_SinResultados anterior) {
    super.didUpdateWidget(anterior);
    // Otra búsqueda que tampoco encontró nada: el mensaje cambió.
    if (anterior.detalle != widget.detalle) _anunciarDespuesDelCuadro();
  }

  /// Después del cuadro, cuando ya se sabe en qué vista está.
  void _anunciarDespuesDelCuadro() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${RutasScreen.sinResultados}. ${widget.detalle}',
        Directionality.of(context),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      key: RutasScreen.claveSinResultados,
      icono: Icons.search_off_rounded,
      titulo: RutasScreen.sinResultados,
      detalle: widget.detalle,
      accion: !widget.confirmada
          // Lo mismo que la tecla de buscar, para quien no la ve: en el
          // navegador es Enter.
          ? OutlinedButton(
              key: RutasScreen.claveBuscarComoLugar,
              onPressed: () =>
                  ref.read(busquedaConfirmadaProvider.notifier).state =
                      widget.termino,
              child: const Text('Buscar como lugar'),
            )
          : widget.lugarNoDisponible
          ? OutlinedButton(
              key: RutasScreen.claveReintentarZona,
              onPressed: () => ref.invalidate(zonaBuscadaProvider),
              child: const Text('Reintentar'),
            )
          : null,
    );
  }
}

/// El lugar que se encontró al confirmar la búsqueda (SCRUM-255), y de
/// dónde salió.
class _NotaZona extends StatelessWidget {
  const _NotaZona({required this.zona});

  final Zona zona;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: RutasScreen.claveNotaZona,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'También las que arrancan en '),
              TextSpan(
                text: zona.nombreCompleto,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
        const SizedBox(height: 2),
        const Text(
          RutasScreen.atribucionZonas,
          style: TextStyle(fontSize: 11, color: AppColors.ink3),
        ),
      ],
    );
  }
}

/// No se pudo preguntar por el lugar (SCRUM-255): lo que se ve coincide por
/// nombre o creador, y conviene que el usuario lo sepa.
class _NotaSinZona extends StatelessWidget {
  const _NotaSinZona({required this.termino});

  final String termino;

  @override
  Widget build(BuildContext context) {
    return Text(
      'No pudimos buscar «$termino» como lugar: estas coinciden por nombre '
      'o creador.',
      key: RutasScreen.claveSinZona,
      style: const TextStyle(fontSize: 13, color: AppColors.ink2),
    );
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
/// mismas tarjetas, mismo espaciado y mismo toque para abrir el detalle. Y
/// el mismo filtro de distancia (SCRUM-274): se aplica aquí para que todas
/// las listas de la sección se filtren igual.
class _ListaDeRutas extends ConsumerWidget {
  const _ListaDeRutas({
    required this.clave,
    required this.encabezado,
    required this.rutas,
  });

  /// Distinta para cada lista: al pasar de una a otra se empieza arriba.
  final Key clave;
  final List<Widget> encabezado;

  /// Todas las de la lista, sin filtrar.
  final List<Ruta> rutas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distancia = ref.watch(rangoDistanciaProvider);
    final visibles = filtrarRutas(rutas, distancia: distancia);
    final encabezado = [
      ...this.encabezado,
      // Si el filtro la deja vacía, se dice debajo del rótulo, que sigue
      // contando qué lista es.
      if (distancia != null && visibles.isEmpty)
        _SinRutasEnRango(rango: distancia),
    ];

    // Al cambiar de rango la lista vuelve arriba: si no, se quedaría a la
    // altura por la que iba la anterior, en medio de otras rutas.
    return KeyedSubtree(
      key: ValueKey(distancia),
      child: ListView.separated(
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
        itemCount: encabezado.length + visibles.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, i) {
          if (i < encabezado.length) return encabezado[i];
          final ruta = visibles[i - encabezado.length];
          return TarjetaRutaExplorar(
            key: TarjetaRutaExplorar.claveDe(ruta.id),
            ruta: ruta,
            // Criterio 5 de HU-29 (SCRUM-250). Con `push`, al cerrar el
            // detalle se vuelve a la lista donde estaba, sin consultarla otra
            // vez. La ruta va en `extra` para que el detalle muestre lo que
            // ya se sabe de ella mientras llega su trazado.
            onTap: () =>
                context.push(DetalleRutaScreen.rutaDe(ruta.id), extra: ruta),
          );
        },
      ),
    );
  }
}

/// Ninguna ruta de la lista mide lo del rango elegido (SCRUM-274).
///
/// Va dentro de la lista y no ocupa la pantalla, como el hueco de un filtro
/// en el catálogo de retos: arriba sigue el rótulo que dice qué lista es, y
/// los rangos siguen a mano para probar con otro.
class _SinRutasEnRango extends ConsumerWidget {
  const _SinRutasEnRango({required this.rango});

  final RangoDistancia rango;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MensajeVacio(
      key: RutasScreen.claveSinRutasEnRango,
      icono: Icons.filter_alt_outlined,
      titulo: RutasScreen.sinRutasEnRango(rango),
      detalle: RutasScreen.pruebaOtroRango,
      // Lo mismo que volver a tocar el rango elegido, que no todos saben que
      // lo quita.
      accion: OutlinedButton(
        key: RutasScreen.claveQuitarFiltro,
        onPressed: () => ref.read(rangoDistanciaProvider.notifier).state = null,
        child: const Text('Quitar el filtro'),
      ),
    );
  }
}

/// El campo para buscar rutas por su nombre o por quien la creó
/// (SCRUM-254), y, al confirmar, por el lugar donde arrancan (SCRUM-255).
///
/// Va fijo debajo del título y no dentro de la lista: así sigue a mano
/// mientras se recorren los resultados.
class _BarraBusqueda extends ConsumerWidget {
  const _BarraBusqueda();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La barra mantiene viva la confirmación mientras exista: sin nadie que
    // la escuche, se borraría antes de que la búsqueda alcanzara a leerla,
    // por ejemplo al escribir y dar Enter en el mismo instante.
    ref.listen(busquedaConfirmadaProvider, (_, _) {});

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: TextField(
        key: RutasScreen.claveBusqueda,
        onChanged: (texto) {
          ref.read(textoBusquedaRutasProvider.notifier).state = texto;
          // Lo confirmado era lo que estaba escrito antes.
          ref.read(busquedaConfirmadaProvider.notifier).state = null;
        },
        // La tecla de buscar (Enter en el navegador) confirma: entonces se
        // busca también el lugar que nombra lo escrito.
        onSubmitted: (texto) =>
            ref.read(busquedaConfirmadaProvider.notifier).state =
                terminoDeBusqueda(texto),
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

/// Los rangos de distancia para filtrar las rutas (SCRUM-273, criterio 1 de
/// HU-37).
///
/// Con los mismos chips que los demás filtros de la app —el catálogo de
/// retos, el historial, el foro— y en el mismo lugar: fijos bajo lo de
/// arriba, así siguen a mano mientras se recorre la lista. Cuando no caben,
/// saltan de línea en vez de cortarse. Uno a la vez, y tocar el elegido lo
/// quita (criterio 4).
class _FiltroDistancia extends ConsumerWidget {
  const _FiltroDistancia();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegido = ref.watch(rangoDistanciaProvider);

    return FilaChips(
      key: RutasScreen.claveFiltroDistancia,
      children: [
        for (final rango in RangoDistancia.values)
          ChipFiltro(
            key: RutasScreen.claveRango(rango),
            texto: rango.etiqueta,
            activo: rango == elegido,
            onTap: () => ref.read(rangoDistanciaProvider.notifier).state =
                rango == elegido ? null : rango,
          ),
      ],
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
