import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/punto_gps.dart';
import '../../models/ruta.dart';
import '../../services/reloj_provider.dart';
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
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// El detalle de una ruta de la comunidad (SCRUM-240).
///
/// Enseña por dónde va, de quién es y cuánto mide. La distancia se ve aquí,
/// sin empezar nada: no hay acción de iniciar la ruta —eso es de otra
/// historia— y el criterio 2 pide justo que no haga falta.
///
/// Del "Detalle de ruta" del prototipo quedan fuera el desnivel y el tiempo
/// estimado: el primero necesitaría la altitud, que no se guarda a propósito
/// desde el Sprint 1, y el segundo depende de él.
class DetalleRutaScreen extends ConsumerWidget {
  const DetalleRutaScreen({required this.rutaId, super.key});

  final String rutaId;

  static const ruta = '/rutas/:rutaId';

  static String rutaDe(String rutaId) =>
      '/rutas/${Uri.encodeComponent(rutaId)}';

  static const claveDistancia = Key('detalle-ruta-distancia');
  static const claveReintentar = Key('detalle-ruta-reintentar');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaProvider(rutaId));

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
  const _Contenido({required this.ruta, required this.ahora});

  final Ruta ruta;
  final DateTime ahora;

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
        _Mapa(trazado: ruta.trazado),
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

/// El trazado sobre el mapa.
class _Mapa extends StatelessWidget {
  const _Mapa({required this.trazado});

  final List<PuntoRuta> trazado;

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
        child: trazado.isEmpty
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
