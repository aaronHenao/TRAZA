import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/punto_gps.dart';
import '../../models/ruta.dart';
import '../../services/reloj_provider.dart';
import '../../services/revision_clasificacion_provider.dart';
import '../../services/rutas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/traza_theme.dart';
import '../../utils/fecha_relativa.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/mapa_trayecto.dart';
import '../../widgets/tarjeta_reto.dart' show TarjetaReto;
import '../../widgets/tarjeta_ruta.dart';
import '../../widgets/tarjeta_ruta_explorar.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';
import 'revisar_clasificacion_screen.dart';

/// El detalle de una ruta de la comunidad (SCRUM-240).
///
/// Enseña por dónde va, de quién es y cuánto mide. La distancia se ve aquí,
/// sin empezar nada: no hay acción de iniciar la ruta —eso es de otra
/// historia— y el criterio 2 pide justo que no haga falta.
///
/// Del "Detalle de ruta" del prototipo quedan fuera el desnivel y el tiempo
/// estimado: el primero necesitaría la altitud, que no se guarda a propósito
/// desde el Sprint 1, y el segundo depende de él.
///
/// Dice también su dificultad, y si un Runner Experto la revisó (SCRUM-264).
class DetalleRutaScreen extends ConsumerWidget {
  const DetalleRutaScreen({required this.rutaId, this.vistaPrevia, super.key});

  final String rutaId;

  /// La ruta tal como se eligió en un listado (SCRUM-250), o null si se
  /// llegó sin ella: desde un enlace o desde el foro.
  ///
  /// Los listados no traen el trazado —pesa, y a la tarjeta le basta la
  /// miniatura—, así que el detalle igual pide la ruta completa. Mientras
  /// llega, con esta se muestra lo que ya se sabe —el nombre, de quién es,
  /// cuánto mide— en vez de una pantalla en blanco.
  final Ruta? vistaPrevia;

  static const ruta = '/rutas/:rutaId';

  static String rutaDe(String rutaId) =>
      '/rutas/${Uri.encodeComponent(rutaId)}';

  /// Quién revisó la dificultad: que fue un Runner Experto, y cuándo
  /// (SCRUM-264, criterio 5 de HU-35).
  static String revisadaPorExperto(DateTime en, DateTime ahora) =>
      'Revisada por un Runner Experto · ${fechaRelativa(en, ahora)}';
  static const sinRevisar = 'Todavía no la revisa un Runner Experto.';
  static const sinDificultadAsignada =
      'Todavía no tiene una dificultad asignada.';

  static const claveDistancia = Key('detalle-ruta-distancia');
  static const claveDificultad = Key('detalle-ruta-dificultad');
  static const claveReintentar = Key('detalle-ruta-reintentar');
  static const claveCargandoTrazado = Key('detalle-ruta-cargando-trazado');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaProvider(rutaId));
    final vistaPrevia = this.vistaPrevia;

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Ruta', onAtras: context.pop),
              Expanded(
                child: switch (ruta) {
                  AsyncData(value: final ruta?) => _Contenido(
                    ruta: ruta,
                    ahora: ref.read(relojProvider)(),
                  ),
                  // Null: no existe, o dejó de estar publicada mientras se
                  // miraba el listado.
                  AsyncData() => const EstadoVacio(
                    icono: Icons.explore_off_outlined,
                    titulo: 'Esta ruta ya no está disponible',
                    detalle:
                        'Puede que su autor la haya retirado o que todavía '
                        'esté en revisión.',
                  ),
                  // Criterio 5 de SCRUM-358: dice que el recorrido no se pudo
                  // mostrar y deja reintentar.
                  AsyncError() => EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    titulo: 'No pudimos mostrar el recorrido',
                    detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                    accion: OutlinedButton(
                      key: claveReintentar,
                      onPressed: () => ref.invalidate(rutaProvider(rutaId)),
                      child: const Text('Reintentar'),
                    ),
                  ),
                  // Mientras llega el trazado, lo que ya se sabe por el
                  // listado (SCRUM-250).
                  _ when vistaPrevia != null => _Contenido(
                    ruta: vistaPrevia,
                    ahora: ref.read(relojProvider)(),
                    cargandoTrazado: true,
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.ruta,
    required this.ahora,
    this.cargandoTrazado = false,
  });

  final Ruta ruta;
  final DateTime ahora;

  /// Si [ruta] es la del listado y su trazado todavía no llega (SCRUM-250).
  final bool cargandoTrazado;

  @override
  Widget build(BuildContext context) {
    final publicada = ruta.fechaPublicacion ?? ruta.fechaCreacion;
    final descripcion = ruta.descripcion?.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _Mapa(trazado: ruta.trazado, cargando: cargandoTrazado),
        const SizedBox(height: AppSpacing.md),
        Text(
          ruta.nombre,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.19,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        // Criterio 4 de SCRUM-241: de quién es y de cuándo.
        Text(
          'Por ${ruta.autorNombre} · ${fechaRelativa(publicada, ahora)}',
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
        const SizedBox(height: AppSpacing.md),
        _Distancia(ruta: ruta),
        const SizedBox(height: AppSpacing.sm),
        _Dificultad(ruta: ruta, ahora: ahora),
        _RevisarClasificacion(rutaId: ruta.id),
        if (descripcion != null && descripcion.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const Text(
            'DESCRIPCIÓN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.66,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            descripcion,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.ink2,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Cuánto mide la ruta, que es lo que esta historia viene a contestar.
class _Distancia extends StatelessWidget {
  const _Distancia({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context) {
    final km = ruta.distanciaKm;

    return TrazaCard(
      key: DetalleRutaScreen.claveDistancia,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.secondaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.linear_scale_rounded,
              size: 20,
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Los km se escriben igual en toda la app.
                  km == null
                      ? TarjetaRuta.sinDistancia
                      : '${TarjetaReto.textoKm(km)} km',
                  style: TextStyle(
                    fontSize: km == null ? 14 : 19,
                    fontWeight: FontWeight.w800,
                    color: km == null ? AppColors.ink2 : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  km == null
                      // Criterio 4: se dice, no se esconde ni se inventa.
                      ? 'Esta ruta se guardó sin su distancia, así que no '
                            'podemos decirte cuánto mide.'
                      : 'Distancia total de la ruta',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La dificultad de la ruta y si un Runner Experto la revisó (SCRUM-264,
/// criterio 5 de HU-35).
///
/// De quién la revisó solo se dice que fue un Runner Experto, y cuándo: eso
/// es lo que le da confianza a quien la va a correr, y el nombre no le
/// agrega nada. Se lee de una vez con el lector de pantalla.
class _Dificultad extends StatelessWidget {
  const _Dificultad({required this.ruta, required this.ahora});

  final Ruta ruta;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final dificultad = ruta.dificultad;
    final revisadaEn = ruta.dificultadRevisadaEn;
    const detalle = TextStyle(fontSize: 12.5, color: AppColors.ink2);

    return MergeSemantics(
      child: TrazaCard(
        key: DetalleRutaScreen.claveDificultad,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.secondaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.signal_cellular_alt_rounded,
                size: 20,
                color: AppColors.secondaryDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dificultad?.etiqueta ?? TarjetaRutaExplorar.sinDificultad,
                    style: TextStyle(
                      fontSize: dificultad == null ? 14 : 19,
                      fontWeight: FontWeight.w800,
                      color: dificultad == null
                          ? AppColors.ink2
                          : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (dificultad != null && revisadaEn != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            DetalleRutaScreen.revisadaPorExperto(
                              revisadaEn,
                              ahora,
                            ),
                            style: detalle,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      dificultad == null
                          ? DetalleRutaScreen.sinDificultadAsignada
                          : DetalleRutaScreen.sinRevisar,
                      style: detalle,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La entrada a revisar la clasificación de la ruta (SCRUM-261), solo para
/// quien la base dice que puede: un Runner Experto que no es su autor
/// (0042). A los demás no se les muestra nada, ni mientras se pregunta.
class _RevisarClasificacion extends ConsumerWidget {
  const _RevisarClasificacion({required this.rutaId});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puede = ref.watch(puedeRevisarClasificacionProvider(rutaId));
    if (puede.valueOrNull != true) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: OutlinedButton.icon(
        key: RevisarClasificacionScreen.claveAbrir,
        onPressed: () =>
            context.push(RevisarClasificacionScreen.rutaDe(rutaId)),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text(RevisarClasificacionScreen.titulo),
      ),
    );
  }
}

/// El trazado sobre el mapa.
class _Mapa extends StatelessWidget {
  const _Mapa({required this.trazado, this.cargando = false});

  final List<PuntoRuta> trazado;

  /// El trazado viene en camino. Sin esto, el de la ruta del listado —que no
  /// lo trae— se tomaría por uno que no se guardó (SCRUM-250).
  final bool cargando;

  /// Los puntos como los pide el mapa, que está hecho para el recorrido de un
  /// entrenamiento. El instante no se usa para dibujar —una ruta no tiene
  /// horas—, así que va uno cualquiera.
  static List<PuntoGps> _paraElMapa(List<PuntoRuta> trazado) => [
    for (final punto in trazado)
      PuntoGps(
        latitud: punto.latitud,
        longitud: punto.longitud,
        capturadoEn: _sinHora,
      ),
  ];

  static final _sinHora = DateTime.utc(2000);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 220,
        child: cargando
            ? const DecoratedBox(
                key: DetalleRutaScreen.claveCargandoTrazado,
                decoration: BoxDecoration(gradient: trazaTrackingGradient),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    semanticsLabel: 'Cargando el recorrido',
                  ),
                ),
              )
            : trazado.isEmpty
            ? const DecoratedBox(
                decoration: BoxDecoration(gradient: trazaTrackingGradient),
                child: Center(
                  child: Text(
                    'Esta ruta no guardó su trazado',
                    style: TextStyle(fontSize: 12.5, color: Colors.white70),
                  ),
                ),
              )
            : MapaTrayecto(puntos: _paraElMapa(trazado)),
      ),
    );
  }
}
