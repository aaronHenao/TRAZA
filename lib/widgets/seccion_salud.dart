import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/metricas_salud.dart';
import '../models/resumen_entrenamiento.dart';
import '../services/salud_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Datos de salud del entrenamiento en el resumen (SCRUM-79).
///
/// Si no hay permiso, el usuario eligió entrenar sin ellos o no se registró
/// nada, no ocupa espacio. Trae su propio margen superior para que el resumen
/// no deje un hueco cuando no aparece.
class SeccionSalud extends ConsumerWidget {
  const SeccionSalud({required this.ventana, super.key});

  /// Toma el tramo del entrenamiento desde el primer punto GPS hasta el final.
  /// Sin puntos, lo calcula con la duración; en ese caso deja por fuera el
  /// tiempo en pausa, así que puede quedar algo corto.
  factory SeccionSalud.deResumen(ResumenEntrenamiento resumen, {Key? key}) {
    final fin = resumen.fechaFin;
    final inicio = resumen.puntos.isEmpty
        ? fin.subtract(resumen.duracion)
        : resumen.puntos.first.capturadoEn;
    return SeccionSalud(ventana: (inicio: inicio, fin: fin), key: key);
  }

  final VentanaEntrenamiento ventana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricas = ref.watch(metricasSaludProvider(ventana)).valueOrNull;
    if (metricas == null) return const SizedBox.shrink();

    final datos = _datosVisibles(metricas);

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite, size: 15, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Datos de salud',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // De a dos por fila, igual que Tiempo y Distancia.
          for (var i = 0; i < datos.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _Dato(dato: datos[i])),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < datos.length
                      ? _Dato(dato: datos[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static List<({String valor, String etiqueta})> _datosVisibles(
    MetricasSalud metricas,
  ) {
    final promedio = metricas.frecuenciaPromedio;
    final maxima = metricas.frecuenciaMaxima;
    final calorias = metricas.calorias;
    final pasos = metricas.pasos;
    return [
      if (promedio != null) (valor: '$promedio lpm', etiqueta: 'FC promedio'),
      if (maxima != null) (valor: '$maxima lpm', etiqueta: 'FC máxima'),
      if (calorias != null) (valor: '$calorias kcal', etiqueta: 'Calorías'),
      if (pasos != null) (valor: '$pasos', etiqueta: 'Pasos'),
    ];
  }
}

/// Misma caja que las métricas del resumen (`.summary-stat`).
class _Dato extends StatelessWidget {
  const _Dato({required this.dato});

  final ({String valor, String etiqueta}) dato;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              dato.valor,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dato.etiqueta,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
