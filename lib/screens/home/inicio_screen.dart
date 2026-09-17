import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/resumen_entrenamiento.dart';
import '../../models/resumen_semana.dart';
import '../../services/inicio_provider.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/navegacion_principal.dart';
import '../../widgets/traza_card.dart';

/// Portada de la app (`screen-inicio` del prototipo completo): a dónde llega
/// el usuario al entrar y desde donde arranca todo.
///
/// Del prototipo se toman el saludo, el bloque de progreso y el botón "+".
/// El nivel, los retos y las rutas quedan fuera: son historias que todavía no
/// existen. En su lugar, el progreso muestra lo que el usuario sí tiene hoy:
/// el objetivo semanal del perfil y sus últimos entrenamientos.
class InicioScreen extends ConsumerWidget {
  const InicioScreen({super.key});

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
            ref.invalidate(resumenSemanaProvider);
            ref.invalidate(ultimosEntrenamientosProvider);
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
              _ProgresoSemanal(),
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

    return Column(
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
    );
  }
}

/// Lo que lleva esta semana frente a su objetivo de distancia, con la barra
/// de progreso del prototipo (`.lv-track`).
class _ProgresoSemanal extends ConsumerWidget {
  const _ProgresoSemanal();

  static const claveAvance = Key('inicio-avance-semanal');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenSemanaProvider);

    return TrazaCard(
      child: switch (resumen) {
        AsyncData(:final value) => _Avance(resumen: value),
        AsyncError() => const _AvisoTarjeta(
          'No pudimos cargar tu progreso de esta semana.',
        ),
        _ => const _AvisoTarjeta('Cargando tu progreso…'),
      },
    );
  }
}

class _Avance extends StatelessWidget {
  const _Avance({required this.resumen});

  final ResumenSemana resumen;

  @override
  Widget build(BuildContext context) {
    final progreso = resumen.progreso;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ESTA SEMANA',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.66,
            color: AppColors.ink2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                resumen.avanceTexto,
                key: _ProgresoSemanal.claveAvance,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Expanded y no Spacer: el conteo queda igual contra el borde
            // derecho, pero con el texto del sistema en grande cede espacio
            // en vez de desbordar la tarjeta.
            Expanded(
              child: Text(
                resumen.entrenamientos == 1
                    ? '1 entrenamiento'
                    : '${resumen.entrenamientos} entrenamientos',
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
              ),
            ),
          ],
        ),
        if (progreso != null) ...[
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 8,
              backgroundColor: AppColors.bgAlt,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Ponte una meta de distancia en tu perfil para seguirla desde aquí.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.ink2,
              height: 1.4,
            ),
          ),
        ],
      ],
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
                onTap: () => context.go('/historial'),
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
