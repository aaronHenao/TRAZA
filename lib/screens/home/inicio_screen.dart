import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/resumen_entrenamiento.dart';
import '../../services/inicio_provider.dart';
import '../../services/notificaciones_provider.dart';
import '../../services/permisos_provider.dart';
import '../../services/progresion_provider.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/bloque_reto_activo.dart';
import '../../widgets/carrusel_rutas_cercanas.dart';
import '../../widgets/indicadores_semana.dart';
import '../../widgets/navegacion_principal.dart';
import '../../widgets/tarjeta_nivel.dart';
import '../../widgets/traza_card.dart';
import '../notificaciones/notificaciones_screen.dart';
import '../onboarding/perfil_screen.dart';

/// Portada de la app (`screen-inicio` del prototipo completo): a dónde llega
/// el usuario al entrar y desde donde arranca todo.
///
/// Del prototipo se toman el saludo, el bloque de progreso y el botón "+".
/// Hoy muestra la tarjeta de nivel (SCRUM-286), el objetivo semanal del perfil
/// y los últimos entrenamientos. Los retos y las rutas llegan con sus propias
/// subtareas, cuando las historias que los producen existan.
class InicioScreen extends ConsumerWidget {
  const InicioScreen({super.key});

  static const claveNotificaciones = Key('inicio-notificaciones');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavegacionPrincipal(
      seccion: SeccionPrincipal.inicio,
      // El "+" del prototipo lleva a elegir la actividad y arrancar.
      onNuevaActividad: () => context.push('/actividad'),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(resumenSemanaProvider)
              ..invalidate(ultimosEntrenamientosProvider)
              // Los retos del indicador y del bloque (SCRUM-287 y SCRUM-288).
              ..invalidate(retosEnCursoProvider)
              // Las rutas del carrusel: la comunidad publica mientras el
              // usuario hace otra cosa (SCRUM-289).
              ..invalidate(rutasCercanasProvider)
              // Y el permiso de ubicación, que el usuario pudo conceder en los
              // ajustes del teléfono (SCRUM-290).
              ..read(permisosProvider.notifier).actualizar()
              // La XP y los niveles de la tarjeta (SCRUM-286).
              ..invalidate(progresionProvider)
              // Y la campana, que es lo que puede haber cambiado sin que el
              // usuario hiciera nada.
              ..invalidate(notificacionesSinLeerProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              // Hueco para que el botón "+" no tape la última tarjeta.
              96,
            ),
            children: const [
              _Saludo(),
              SizedBox(height: AppSpacing.lg),
              // El nivel primero, como en el prototipo (SCRUM-286).
              TarjetaNivel(),
              SizedBox(height: AppSpacing.md),
              // Los tres indicadores de la semana (SCRUM-287).
              IndicadoresSemana(),
              SizedBox(height: AppSpacing.lg),
              // El reto que hay que atender hoy (SCRUM-288).
              BloqueRetoActivo(),
              SizedBox(height: AppSpacing.lg),
              // Las rutas de la comunidad, de lado (SCRUM-289).
              CarruselRutasCercanas(),
              SizedBox(height: AppSpacing.lg),
              _UltimosEntrenamientos(),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.greet-row` del prototipo: el saludo con el nombre de la persona.
class _Saludo extends ConsumerWidget {
  const _Saludo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nombre = ref.watch(nombreUsuarioProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                nombre == null ? 'Hola' : 'Hola, $nombre',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Vamos por tu meta semanal',
                style: TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
            ],
          ),
        ),
        // La campana de la `greet-row` del prototipo (SCRUM-241).
        const Padding(padding: EdgeInsets.only(top: 8), child: _Campana()),
      ],
    );
  }
}

/// Acceso a las notificaciones, con lo que lleva sin leer.
///
/// El contador no se pinta como error ni bloquea nada: si no se pudo contar,
/// la campana sale sola y la bandeja sigue abriéndose.
class _Campana extends ConsumerWidget {
  const _Campana();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mientras la portada esté a la vista, la campana escucha: un aviso
    // llega cuando el usuario no lo está pidiendo.
    ref.watch(notificacionesEnVivoProvider);
    final sinLeer = ref.watch(notificacionesSinLeerProvider).valueOrNull ?? 0;

    return IconButton(
      key: InicioScreen.claveNotificaciones,
      onPressed: () => context.push(NotificacionesScreen.ruta),
      tooltip: 'Notificaciones',
      icon: Badge(
        isLabelVisible: sinLeer > 0,
        backgroundColor: AppColors.danger,
        // Pasado de nueve, el número exacto no le dice nada a nadie.
        label: Text(sinLeer > 9 ? '9+' : '$sinLeer'),
        child: const Icon(Icons.notifications_none_rounded, size: 22),
      ),
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.bgAlt,
        fixedSize: const Size(38, 38),
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Los últimos entrenamientos, con acceso al historial completo.
class _UltimosEntrenamientos extends ConsumerWidget {
  const _UltimosEntrenamientos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ultimos = ref.watch(ultimosEntrenamientosProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'ÚLTIMOS ENTRENAMIENTOS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.52,
                  color: AppColors.ink2,
                ),
              ),
            ),
            if (ultimos.valueOrNull?.isNotEmpty ?? false)
              GestureDetector(
                // El historial completo vive en el perfil desde SCRUM-285.
                onTap: () =>
                    context.go(PerfilScreen.rutaCon(PestanaPerfil.actividades)),
                child: const Text(
                  'Ver todos',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        switch (ultimos) {
          AsyncData(value: final lista) when lista.isEmpty =>
            const _AvisoTarjeta(
              'Todavía no has entrenado. Toca el botón + para empezar.',
            ),
          AsyncData(value: final lista) => Column(
            children: [
              for (final entrenamiento in lista) ...[
                _FilaEntrenamiento(entrenamiento: entrenamiento),
                if (entrenamiento != lista.last)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
          AsyncError() => const _AvisoTarjeta(
            'No pudimos cargar tus entrenamientos.',
          ),
          _ => const _AvisoTarjeta('Cargando…'),
        },
      ],
    );
  }
}

/// Una línea del historial, con el mismo formato que la pantalla completa.
class _FilaEntrenamiento extends ConsumerWidget {
  const _FilaEntrenamiento({required this.entrenamiento});

  final ResumenEntrenamiento entrenamiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.read(relojProvider)();

    return TrazaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
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
              Icons.directions_run,
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
                  entrenamiento.subtitulo(ahora),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entrenamiento.distancia} · ${entrenamiento.tiempo}',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensaje corto dentro de una tarjeta, para los estados sin datos.
class _AvisoTarjeta extends StatelessWidget {
  const _AvisoTarjeta(this.mensaje);

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Text(
        mensaje,
        style: const TextStyle(
          fontSize: 12.5,
          color: AppColors.ink2,
          height: 1.4,
        ),
      ),
    );
  }
}
