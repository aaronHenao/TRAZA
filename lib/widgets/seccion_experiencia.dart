import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/ascenso.dart';
import '../models/avance_reto.dart';
import '../models/experiencia_ganada.dart';
import '../models/progresion.dart';
import '../models/regla_experiencia.dart';
import '../models/resumen_entrenamiento.dart';
import '../services/experiencia_provider.dart';
import '../services/retos_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'tarjeta_reto.dart';

/// La XP que dejó el entrenamiento, en su resumen (SCRUM-207).
///
/// La XP sale solo de los retos: si el entrenamiento no completó ninguno no
/// muestra "+0 XP", sino cómo se gana. Recién finalizado, muestra cada reto
/// que avanzó con su barra y cuántos km le sumó; los que completó, con la XP
/// que pagaron. También dice por qué los km no contaron para los retos si fue
/// el caso y el nivel con su progreso (SCRUM-198). Si el entrenamiento lo
/// hizo subir de nivel, lo anuncia arriba (SCRUM-199).
///
/// Un entrenamiento anterior a `0018_xp_solo_por_retos.sql` puede traer XP de
/// actividad, que se conservó: entonces aparece en el desglose.
///
/// Trae su propio margen superior, como `SeccionSalud`.
class SeccionExperiencia extends ConsumerWidget {
  const SeccionExperiencia({
    required this.entrenamientoId,
    required this.resumen,
    this.recienFinalizado = false,
    super.key,
  });

  final String entrenamientoId;

  /// El entrenamiento: su actividad, distancia y fecha deciden qué retos
  /// avanzó.
  final ResumenEntrenamiento resumen;

  /// Solo en el resumen que sigue a "Finalizar". Desde el historial, la XP y
  /// los km de entrenamientos posteriores falsearían qué niveles cruzó este y
  /// cuánto avanzó cada reto: no se anuncia el ascenso ni se pintan barras.
  final bool recienFinalizado;

  static const claveTotal = Key('seccion-experiencia-total');
  static const claveSinXp = Key('seccion-experiencia-sin-xp');
  static const claveAscenso = Key('seccion-experiencia-ascenso');
  static const claveNivel = Key('seccion-experiencia-nivel');
  static const claveAvanceNivel = Key('seccion-experiencia-avance-nivel');
  static const claveSinRetos = Key('seccion-experiencia-sin-retos');

  static Key claveAvanceDe(String retoId) =>
      Key('seccion-experiencia-reto-$retoId');

  /// Lo que se ve en lugar de "+0 XP".
  static const textoSinXp = 'Suma XP completando retos';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proveedor = experienciaDeEntrenamientoProvider(entrenamientoId);
    final experiencia = ref.watch(proveedor);

    // Los retos son un dato secundario: si no cargan, la XP se muestra igual.
    // Solo se piden si los km contaron; si no, no avanzó ninguno.
    List<AvanceReto>? avances;
    final ganada = experiencia.valueOrNull;
    if (recienFinalizado &&
        ganada != null &&
        ganada.ajuste == AjusteExperiencia.ninguno) {
      final misRetos = ref.watch(misRetosProvider).valueOrNull;
      if (misRetos != null) {
        avances = AvanceReto.delEntrenamiento(
          misRetos: misRetos,
          xp: ganada,
          resumen: resumen,
        );
      }
    }

    final contenido = experiencia.when(
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
          : _Detalle(
              xp,
              avances: avances,
              nombreActividad: resumen.nombreActividad,
            ),
    );

    // El nivel tampoco es imprescindible.
    final nivel = ref
        .watch(nivelTrasEntrenamientoProvider(entrenamientoId))
        .valueOrNull;
    final ascenso = recienFinalizado ? nivel?.ascenso : null;

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
                  const SizedBox(height: 14),
                  _Nivel(nivel.progresion),
                ],
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
  const _Detalle(
    this.xp, {
    required this.avances,
    required this.nombreActividad,
  });

  final ExperienciaDeEntrenamiento xp;

  /// Los retos que avanzó, o null si no se pueden mostrar: desde el
  /// historial, sin los retos cargados o si los km no contaron.
  final List<AvanceReto>? avances;

  final String nombreActividad;

  @override
  Widget build(BuildContext context) {
    final motivo = _motivo(xp.ajuste);
    final avances = this.avances;

    // Un reto completado que ya tiene su fila con barra no se repite como
    // línea del desglose.
    final conFila = {
      for (final avance in avances ?? const <AvanceReto>[])
        if (avance.completadoAhora) avance.reto.reto.id,
    };
    final sinFila = [
      for (final reto in xp.retos)
        if (!conFila.contains(reto.retoId)) reto,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (xp.total > 0) _CabeceraXp(xp.total) else const _CabeceraSinXp(),
        // El desglose solo aporta con varias fuentes. La actividad solo trae
        // XP en entrenamientos anteriores a que el libre dejara de darla.
        if (xp.retos.isNotEmpty &&
            (xp.xpActividad > 0 || sinFila.isNotEmpty)) ...[
          const SizedBox(height: 8),
          if (xp.xpActividad > 0) _Linea('Actividad', xp.xpActividad),
          for (final reto in sinFila)
            _Linea('Reto «${reto.nombre}» completado', reto.xp),
        ],
        if (avances != null) ...[
          const SizedBox(height: 12),
          if (avances.isEmpty)
            _SinRetos(nombreActividad)
          else ...[
            const Text(
              'Tus retos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
            for (final avance in avances) ...[
              const SizedBox(height: 8),
              _FilaAvance(avance),
            ],
          ],
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

  /// Por qué los km no contaron para los retos.
  ///
  /// Con menos del mínimo o con el tope lleno los km sí contaban: esos dos
  /// solo recortaban la XP de actividad, que ya no existe.
  static String? _motivo(AjusteExperiencia ajuste) => switch (ajuste) {
    AjusteExperiencia.ninguno ||
    AjusteExperiencia.menosDelMinimo ||
    AjusteExperiencia.topeDiario => null,
    AjusteExperiencia.velocidadImposible =>
      'El promedio superó los ${ReglaExperiencia.velocidadMaximaKmH.round()} '
          'km/h, así que este entrenamiento no cuenta para tus retos.',
    AjusteExperiencia.sinDatos =>
      'Sin distancia registrada, este entrenamiento no cuenta para tus retos.',
  };
}

/// La XP que ganó, cuando hay XP que mostrar.
class _CabeceraXp extends StatelessWidget {
  const _CabeceraXp(this.total);

  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          '+$total XP',
          key: SeccionExperiencia.claveTotal,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

/// En lugar de "+0 XP": cómo se gana la XP.
class _CabeceraSinXp extends StatelessWidget {
  const _CabeceraSinXp();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.bolt_rounded, size: 18, color: AppColors.primary),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            SeccionExperiencia.textoSinXp,
            key: SeccionExperiencia.claveSinXp,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// Un reto que avanzó el entrenamiento: su barra con lo que llevaba y lo que
/// sumó hoy, y la XP si lo completó.
class _FilaAvance extends StatelessWidget {
  const _FilaAvance(this.avance);

  final AvanceReto avance;

  @override
  Widget build(BuildContext context) {
    final reto = avance.reto.reto;
    final completado = avance.completadoAhora;
    final meta = TarjetaReto.textoKm(reto.metaKm);

    return Container(
      key: SeccionExperiencia.claveAvanceDe(reto.id),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (completado) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  reto.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Lo que paga: ganado si lo completó, por ganar si no.
              InsigniaReto(
                texto: completado
                    ? '+${avance.xpGanada} XP'
                    : '${reto.xpOtorgada} XP',
                fondo: completado ? AppColors.primaryTint : AppColors.bgAlt,
                color: completado ? AppColors.primaryDark : AppColors.ink3,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BarraAvance(
            antes: avance.progresoAntes,
            despues: avance.progresoDespues,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  completado
                      ? '¡Completado! $meta de $meta km'
                      : '${TarjetaReto.textoKm(avance.reto.progresoKm)} de '
                            '$meta km',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
              ),
              Text(
                '+${TarjetaReto.textoKm(avance.kmAportados)} km',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barra de un reto en dos tramos: lo que llevaba antes, en tono claro, y lo
/// que sumó este entrenamiento, en el color principal. El tramo nuevo crece
/// al aparecer para que se note qué parte es de hoy.
class _BarraAvance extends StatelessWidget {
  const _BarraAvance({required this.antes, required this.despues});

  /// Entre 0 y 1.
  final double antes;
  final double despues;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Progreso del reto',
      value: '${(despues * 100).round()} %',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          height: 8,
          child: LayoutBuilder(
            builder: (context, restricciones) {
              final ancho = restricciones.maxWidth;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: antes, end: despues),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, hasta, _) => Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: AppColors.bgAlt),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: ancho * hasta,
                      child: const ColoredBox(color: AppColors.primary),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: ancho * antes,
                      child: const ColoredBox(color: AppColors.secondary),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Los km contaron, pero no había ningún reto de esta actividad que avanzar.
class _SinRetos extends StatelessWidget {
  const _SinRetos(this.nombreActividad);

  final String nombreActividad;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: SeccionExperiencia.claveSinRetos,
      children: [
        Expanded(
          child: Text(
            'No tienes retos de $nombreActividad en curso.',
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/retos'),
          child: const Text('Ver retos'),
        ),
      ],
    );
  }
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
