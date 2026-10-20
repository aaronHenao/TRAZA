import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resumen_semana.dart';
import '../services/inicio_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// Los tres indicadores de la semana en la portada (SCRUM-287, criterio 2 de
/// SCRUM-283): kilómetros, actividades y retos activos.
///
/// Reemplaza el bloque de progreso semanal del Sprint 1, que mostraba una sola
/// cifra con su barra. La meta de distancia del perfil no se pierde: cuando
/// hay una, los kilómetros se leen contra ella (`9.2 / 15`).
///
/// Los kilómetros y las actividades salen del mismo resumen; los retos van por
/// su cuenta, así que si esa consulta falla las otras dos cifras se muestran
/// igual. Las cajas son las del prototipo (`.stat-box`), las mismas del
/// resumen del entrenamiento.
class IndicadoresSemana extends ConsumerWidget {
  const IndicadoresSemana({super.key});

  static const clave = Key('inicio-indicadores-semana');
  static const claveKilometros = Key('inicio-km-semana');
  static const claveActividades = Key('inicio-actividades-semana');
  static const claveRetos = Key('inicio-retos-activos');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenSemanaProvider);

    return TrazaCard(
      key: clave,
      child: Column(
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
          switch (resumen) {
            AsyncData(:final value) => _Cifras(resumen: value),
            AsyncError() => const _Aviso(
              'No pudimos cargar tu semana. Desliza hacia abajo para '
              'volver a intentarlo.',
            ),
            _ => const _Aviso('Cargando tu semana…'),
          },
        ],
      ),
    );
  }
}

class _Cifras extends ConsumerWidget {
  const _Cifras({required this.resumen});

  final ResumenSemana resumen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Los retos no bloquean las otras dos cifras: mientras se consultan, o si
    // la consulta falla, su caja queda en guion y las demás se leen igual.
    final retos = ref.watch(retosEnCursoProvider).valueOrNull?.length;
    final actividades = resumen.entrenamientos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Indicador(
                clave: IndicadoresSemana.claveKilometros,
                // Con meta configurada, los kilómetros se leen contra ella.
                valor: resumen.avanceSinUnidad,
                etiqueta: 'km',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Indicador(
                clave: IndicadoresSemana.claveActividades,
                valor: '$actividades',
                etiqueta: actividades == 1 ? 'actividad' : 'actividades',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Indicador(
                clave: IndicadoresSemana.claveRetos,
                valor: retos == null ? '—' : '$retos',
                etiqueta: retos == 1 ? 'reto activo' : 'retos activos',
              ),
            ),
          ],
        ),
        // Sin meta no hay con qué comparar los kilómetros: se dice dónde se
        // pone, que es lo que convierte la cifra en un objetivo.
        if (resumen.metaKilometros == null) ...[
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

/// `.stat-box`: un valor grande con su etiqueta debajo.
class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.clave,
    required this.valor,
    required this.etiqueta,
  });

  final Key clave;
  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          // "12.4 / 15" en la pantalla más estrecha, o el texto del sistema en
          // grande, no deben desbordar la caja.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              key: clave,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              etiqueta,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 12.5,
        color: AppColors.ink2,
        height: 1.4,
      ),
    );
  }
}
