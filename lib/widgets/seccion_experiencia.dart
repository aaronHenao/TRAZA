import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/experiencia_ganada.dart';
import '../models/regla_experiencia.dart';
import '../services/experiencia_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// La XP que dejó el entrenamiento, en su resumen (SCRUM-207).
///
/// Muestra lo ganado por la actividad y por cada reto completado, por qué la
/// actividad dio menos si fue el caso, y siempre el tope del día: quien quiera
/// sumar mucho en un solo día lo sabe antes de chocar con él.
///
/// Trae su propio margen superior, como `SeccionSalud`.
class SeccionExperiencia extends ConsumerWidget {
  const SeccionExperiencia({required this.entrenamientoId, super.key});

  final String entrenamientoId;

  static const claveTotal = Key('seccion-experiencia-total');

  /// La nota del tope, armada con las constantes de la regla.
  static String get notaTope {
    final km = ReglaExperiencia.topeDiarioMetros ~/ 1000;
    return 'La actividad da hasta ${ReglaExperiencia.topeDiarioXp} XP al día '
        '($km km). Los retos no tienen tope.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proveedor = experienciaDeEntrenamientoProvider(entrenamientoId);

    final contenido = ref
        .watch(proveedor)
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const _Aviso('Calculando tu XP…'),
          error: (_, _) => _Aviso(
            'No pudimos cargar tu XP.',
            onReintentar: () => ref.invalidate(proveedor),
          ),
          // Sin fila de actividad el entrenamiento no se procesó: es anterior
          // a la XP o la XP falló al cerrarlo.
          data: (xp) => xp == null
              ? const _Aviso('Este entrenamiento no tiene XP registrada.')
              : _Detalle(xp),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            contenido,
            const SizedBox(height: 10),
            Text(
              notaTope,
              style: const TextStyle(fontSize: 11, color: AppColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle(this.xp);

  final ExperienciaDeEntrenamiento xp;

  @override
  Widget build(BuildContext context) {
    final motivo = _motivo(xp.ajuste);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'XP obtenida',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '+${xp.total} XP',
              key: SeccionExperiencia.claveTotal,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        // El desglose solo aporta si hay algo más que la actividad.
        if (xp.retos.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Linea('Actividad', xp.xpActividad),
          for (final reto in xp.retos)
            _Linea('Reto «${reto.nombre}» completado', reto.xp),
        ],
        if (motivo != null) ...[
          const SizedBox(height: 8),
          Text(
            motivo,
            style: const TextStyle(fontSize: 12, color: AppColors.ink),
          ),
        ],
      ],
    );
  }

  /// Por qué la actividad dio menos de lo que daría su distancia.
  static String? _motivo(AjusteExperiencia ajuste) => switch (ajuste) {
    AjusteExperiencia.ninguno => null,
    AjusteExperiencia.topeDiario =>
      'Llegaste al tope de XP del día. Tus km siguen contando para tus retos.',
    AjusteExperiencia.menosDelMinimo =>
      'La actividad suma XP desde el primer kilómetro.',
    AjusteExperiencia.velocidadImposible =>
      'El promedio superó los ${ReglaExperiencia.velocidadMaximaKmH.round()} '
          'km/h, así que esta actividad no suma XP.',
    AjusteExperiencia.sinDatos =>
      'Sin distancia registrada, esta actividad no suma XP.',
  };
}

class _Linea extends StatelessWidget {
  const _Linea(this.concepto, this.xp);

  final String concepto;
  final int xp;

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontSize: 12.5, color: AppColors.ink2);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(child: Text(concepto, style: estilo)),
          Text(
            '+$xp XP',
            style: estilo.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto, {this.onReintentar});

  final String texto;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
          ),
        ),
        if (onReintentar != null)
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
      ],
    );
  }
}
