import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/punto_gps.dart';
import '../../models/ruta.dart';
import '../../services/revision_rutas_provider.dart';
import '../../services/rutas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/traza_theme.dart';
import '../../utils/fecha_relativa.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/dialogo_motivo_rechazo.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/mapa_trayecto.dart';
import '../../widgets/tarjeta_reto.dart' show TarjetaReto;
import '../../widgets/tarjeta_revision_ruta.dart';
import '../../widgets/tarjeta_ruta.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// La bandeja de revisión de rutas del administrador (SCRUM-327).
///
/// Es la primera revisión: lista lo recién enviado, lo que más tiempo lleva
/// esperando primero. Se decide desde la tarjeta o desde el detalle, que
/// enseña el trazado. Lo que aprueba pasa a "Rutas por clasificar", la
/// bandeja del Runner Experto (SCRUM-363).
///
/// La pantalla no comprueba el rol: la envuelve `SoloAdministrador` en el
/// router, y la base solo deja leer y decidir al administrador (SCRUM-332).
class RevisionRutasScreen extends ConsumerWidget {
  const RevisionRutasScreen({super.key});

  /// Se abre desde el panel del administrador.
  static const ruta = '/admin/rutas';

  static String detalleDe(String rutaId) =>
      '$ruta/${Uri.encodeComponent(rutaId)}';

  static const claveLista = Key('revision-rutas-lista');
  static const claveReintentar = Key('revision-rutas-reintentar');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(rutasPorRevisarProvider);

    void recargar() => ref.invalidate(rutasPorRevisarProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Revisión de rutas', onAtras: context.pop),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (pendientes) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const _SinPendientes(),
                    AsyncData(value: final lista) => ListView.separated(
                      key: claveLista,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      itemCount: lista.length + 1,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) {
                        if (i == 0) return const _Explicacion();
                        final ruta = lista[i - 1];
                        return TarjetaRevisionRuta(
                          ruta: ruta,
                          onAprobar: () =>
                              decidirRevisionRuta(context, ref, ruta, true),
                          onRechazar: () =>
                              decidirRevisionRuta(context, ref, ruta, false),
                          onTap: () => context.push(detalleDe(ruta.id)),
                        );
                      },
                    ),
                    AsyncError() => _ErrorDeCarga(onReintentar: recargar),
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

/// Aprueba o rechaza [ruta] y avisa cómo quedó. Rechazar pide antes el
/// motivo (SCRUM-330), que es lo que leerá el autor.
///
/// La usan el administrador, aquí, y el Runner Experto para rechazar desde
/// el detalle de la ruta (`DetalleRutaScreen`).
///
/// Devuelve true si la decisión quedó guardada.
Future<bool> decidirRevisionRuta(
  BuildContext context,
  WidgetRef ref,
  Ruta ruta,
  bool aprobar,
) async {
  String? motivo;
  if (!aprobar) {
    motivo = await pedirMotivoRechazo(
      context,
      titulo: 'Rechazar «${ruta.nombre}»',
    );
    if (motivo == null) return false;
  }

  final resultado = await ref
      .read(decisionRevisionRutaProvider)
      .decidir(ruta, aprobar: aprobar, motivo: motivo);
  if (!context.mounted) return resultado is RutaRevisada;

  mostrarToast(context, switch (resultado) {
    RutaRevisada(:final ruta) => DecisionRevisionRuta.hecho(ruta),
    RevisionSinMotivo(:final mensaje) => mensaje,
    RevisionYaResuelta() => DecisionRevisionRuta.yaResuelta,
    RevisionNoGuardada(:final mensaje) => mensaje,
  });
  return resultado is RutaRevisada;
}

/// Qué le toca decidir al administrador, encima de la lista.
class _Explicacion extends StatelessWidget {
  const _Explicacion();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Eres la primera revisión. Lo que apruebes pasa a un Runner Experto, '
      'que le asigna la dificultad; nada de esto lo ve todavía la comunidad.',
      style: TextStyle(fontSize: 12.5, color: AppColors.ink2, height: 1.45),
    );
  }
}

class _SinPendientes extends StatelessWidget {
  const _SinPendientes();

  @override
  Widget build(BuildContext context) {
    // `EstadoVacio` ya se desplaza: el RefreshIndicator funciona también
    // con la bandeja vacía.
    return const EstadoVacio(
      icono: Icons.task_alt_rounded,
      titulo: 'No hay rutas por revisar',
      detalle: 'Cuando alguien publique una ruta, aparecerá aquí.',
    );
  }
}

class _ErrorDeCarga extends StatelessWidget {
  const _ErrorDeCarga({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      icono: Icons.cloud_off_outlined,
      titulo: 'No pudimos cargar las rutas',
      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      accion: OutlinedButton(
        key: RevisionRutasScreen.claveReintentar,
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    );
  }
}

/// Una ruta por revisar, con su trazado (SCRUM-327).
///
/// Lee la ruta con `rutaProvider` (SCRUM-240): la base deja verla al
/// administrador siempre. Solo ofrece decidir si la ruta sigue esperándolo;
/// si ya se decidió, enseña en qué quedó.
class RevisionRutaScreen extends ConsumerWidget {
  const RevisionRutaScreen({required this.rutaId, super.key});

  final String rutaId;

  static const claveAprobar = Key('revision-ruta-detalle-aprobar');
  static const claveRechazar = Key('revision-ruta-detalle-rechazar');
  static const claveMapa = Key('revision-ruta-detalle-mapa');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaProvider(rutaId));

    Future<void> decidir(Ruta ruta, bool aprobar) async {
      final hecho = await decidirRevisionRuta(context, ref, ruta, aprobar);
      if (hecho && context.mounted) context.pop();
    }

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Revisar ruta', onAtras: context.pop),
              Expanded(
                child: switch (ruta) {
                  AsyncData(value: final ruta?) => _DetalleRevision(
                    ruta: ruta,
                    pendienteDeEstaEtapa: ruta.estado == EstadoRuta.enRevision,
                    onAprobar: () => decidir(ruta, true),
                    onRechazar: () => decidir(ruta, false),
                  ),
                  AsyncData() => const EstadoVacio(
                    icono: Icons.explore_off_outlined,
                    titulo: 'Esta ruta ya no está disponible',
                    detalle: 'Puede que otro revisor ya la haya decidido.',
                  ),
                  AsyncError() => EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    titulo: 'No pudimos cargar la ruta',
                    detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                    accion: OutlinedButton(
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

class _DetalleRevision extends StatelessWidget {
  const _DetalleRevision({
    required this.ruta,
    required this.pendienteDeEstaEtapa,
    required this.onAprobar,
    required this.onRechazar,
  });

  final Ruta ruta;
  final bool pendienteDeEstaEtapa;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    final descripcion = ruta.descripcion?.trim();
    final km = ruta.distanciaKm;
    final motivo = ruta.motivoRechazo;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: [
              _Trazado(trazado: ruta.trazado),
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
              Text(
                'Por ${ruta.autorNombre}',
                style: const TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
              const SizedBox(height: AppSpacing.sm),
              DatoRevision(etiqueta: 'Estado', valor: ruta.estado.etiqueta),
              DatoRevision(
                etiqueta: 'Distancia',
                valor: km == null
                    ? TarjetaRuta.sinDistancia
                    : '${TarjetaReto.textoKm(km)} km',
              ),
              DatoRevision(
                etiqueta: 'Enviada',
                valor: fechaExacta(ruta.fechaCreacion),
              ),
              if (motivo != null)
                DatoRevision(
                  etiqueta: 'Motivo del rechazo',
                  valor: motivo,
                  color: AppColors.danger,
                ),
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
                descripcion == null || descripcion.isEmpty
                    ? 'Su autor no escribió una descripción.'
                    : descripcion,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.ink2,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (pendienteDeEstaEtapa)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: BotonesRevision(
              claveAprobar: RevisionRutaScreen.claveAprobar,
              claveRechazar: RevisionRutaScreen.claveRechazar,
              onAprobar: onAprobar,
              onRechazar: onRechazar,
            ),
          ),
      ],
    );
  }
}

/// El trazado sobre el mapa, que es lo que más pesa al decidir.
class _Trazado extends StatelessWidget {
  const _Trazado({required this.trazado});

  final List<PuntoRuta> trazado;

  /// El mapa está hecho para el recorrido de un entrenamiento y pide un
  /// instante por punto; una ruta no tiene horas, así que va uno cualquiera.
  static final _sinHora = DateTime.utc(2000);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: RevisionRutaScreen.claveMapa,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 240,
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
            : MapaTrayecto(
                puntos: [
                  for (final punto in trazado)
                    PuntoGps(
                      latitud: punto.latitud,
                      longitud: punto.longitud,
                      capturadoEn: _sinHora,
                    ),
                ],
              ),
      ),
    );
  }
}
