import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ascenso.dart';
import '../models/experiencia_ganada.dart';
import '../models/progresion.dart';
import '../models/regla_experiencia.dart';
import '../services/experiencia_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// La XP que dejó el entrenamiento, en su resumen (SCRUM-207).
///
/// Muestra lo ganado por la actividad y por cada reto completado, por qué la
/// actividad dio menos si fue el caso, el nivel con su progreso (SCRUM-198) y
/// siempre el tope del día: quien quiera sumar mucho en un solo día lo sabe
/// antes de chocar con él. Si el entrenamiento lo hizo subir de nivel, lo
/// anuncia arriba (SCRUM-199).
///
/// Trae su propio margen superior, como `SeccionSalud`.
class SeccionExperiencia extends ConsumerWidget {
  const SeccionExperiencia({
    required this.entrenamientoId,
    this.anunciarAscenso = false,
    super.key,
  });

  final String entrenamientoId;

  /// Solo en el resumen recién finalizado. Desde el historial, la XP ganada
  /// después falsearía qué niveles cruzó este entrenamiento.
  final bool anunciarAscenso;

  static const claveTotal = Key('seccion-experiencia-total');
  static const claveAscenso = Key('seccion-experiencia-ascenso');
  static const claveNivel = Key('seccion-experiencia-nivel');
  static const claveAvanceNivel = Key('seccion-experiencia-avance-nivel');

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

    // El nivel es un dato secundario: si no carga, la XP se muestra igual.
    final nivel = ref
        .watch(nivelTrasEntrenamientoProvider(entrenamientoId))
        .valueOrNull;
    final ascenso = anunciarAscenso ? nivel?.ascenso : null;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ascenso != null) ...[
            _BannerAscenso(ascenso),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                contenido,
                if (nivel != null && nivel.progresion.hayNiveles) ...[
                  const SizedBox(height: 12),
                  _Nivel(nivel.progresion),
                ],
                const SizedBox(height: 10),
                Text(
                  notaTope,
                  style: const TextStyle(fontSize: 11, color: AppColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El aviso de que subió de nivel (SCRUM-199).
///
/// No hay que confirmarlo ni cerrarlo: está en la pantalla que sigue siempre a
/// "Finalizar". Entra con una animación corta para que se sienta como un
/// logro y no como un dato más.
class _BannerAscenso extends StatelessWidget {
  const _BannerAscenso(this.ascenso);

  final Ascenso ascenso;

  @override
  Widget build(BuildContext context) {
    final cruzados = ascenso.niveles.length;
    final titulo = cruzados == 1
        ? '¡Subiste a ${ascenso.nivelFinal.nombre}!'
        : '¡Subiste $cruzados niveles!';
    final detalle = cruzados == 1
        ? 'Lo lograste con este entrenamiento.'
        : 'Llegaste a ${ascenso.nivelFinal.nombre} con este entrenamiento.';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
      ),
      child: Container(
        key: SeccionExperiencia.claveAscenso,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 30,
              color: AppColors.accentInk,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.accentInk,
                    ),
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

/// El nivel en que quedó y cuánto le falta para el siguiente (SCRUM-198).
class _Nivel extends StatelessWidget {
  const _Nivel(this.progresion);

  final Progresion progresion;

  @override
  Widget build(BuildContext context) {
    final siguiente = progresion.siguienteNivel;
    final nota = siguiente == null
        ? 'Estás en el nivel más alto.'
        : 'Te faltan ${progresion.experienciaFaltante} XP para '
              '${siguiente.nombre}.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // SCRUM-200: por debajo del primer umbral todavía no hay nivel.
          'Nivel: ${progresion.nivelActual?.nombre ?? 'aún sin nivel'}',
          key: SeccionExperiencia.claveNivel,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            key: SeccionExperiencia.claveAvanceNivel,
            // En el último nivel no hay tramo que recorrer: llena.
            value: progresion.avance ?? 1,
            minHeight: 6,
            backgroundColor: AppColors.bg,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(nota, style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
      ],
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
