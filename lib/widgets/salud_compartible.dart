import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/metricas_salud.dart';
import '../services/salud_service.dart';

/// Datos de salud para la foto que se comparte del entrenamiento (SCRUM-84).
///
/// Va encima de la foto, así que usa texto claro con sombra. Sigue la misma
/// regla que el resumen ([metricasSaludProvider]): sin permiso, si el usuario
/// eligió entrenar sin datos de salud o si no se registró nada, no dibuja
/// nada y la foto sale sin ellos.
///
/// La foto compartible todavía no existe (ver `docs/deudas.md`). Quien la haga
/// solo tiene que ponerlo encima de la imagen:
///
/// ```dart
/// Stack(children: [
///   foto,
///   Positioned(left: 16, bottom: 16, child: SaludCompartible(ventana: ventana)),
/// ])
/// ```
class SaludCompartible extends ConsumerWidget {
  const SaludCompartible({required this.ventana, super.key});

  final VentanaEntrenamiento ventana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricas = ref.watch(metricasSaludProvider(ventana)).valueOrNull;
    if (metricas == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (icono, texto) in textosPara(metricas))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 16, color: Colors.white, shadows: _sombra),
              const SizedBox(width: 4),
              Text(
                texto,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: _sombra,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Sombra para que se lea sobre cualquier foto, clara u oscura.
  static const _sombra = [
    Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  /// Qué se escribe en la foto, en orden. Solo los datos que se registraron.
  static List<(IconData, String)> textosPara(MetricasSalud metricas) {
    final promedio = metricas.frecuenciaPromedio;
    final calorias = metricas.calorias;
    final pasos = metricas.pasos;
    return [
      if (promedio != null) (Icons.favorite, '$promedio lpm'),
      if (calorias != null) (Icons.local_fire_department, '$calorias kcal'),
      if (pasos != null) (Icons.directions_walk, '$pasos pasos'),
    ];
  }
}
