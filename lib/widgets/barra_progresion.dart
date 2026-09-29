import 'package:flutter/material.dart';

import '../models/progresion.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Qué tan cerca está el corredor del siguiente nivel (SCRUM-188).
///
/// Dibuja el tramo que va de un umbral al otro y cuánto lleva recorrido, para
/// que se vea de un vistazo lo que el texto dice con números. Encima lleva la
/// cuenta del tramo —"100 de 400 XP"— porque una barra a secas no dice de
/// cuánto es el trecho.
///
/// No calcula nada: el avance lo trae [Progresion]. Si no hay siguiente nivel
/// no se dibuja —no habría meta que representar—, y de eso se encarga quien la
/// use.
class BarraProgresion extends StatelessWidget {
  const BarraProgresion({required this.progresion, super.key});

  static const clave = Key('progresion-barra');
  static const claveResumen = Key('progresion-barra-resumen');

  final Progresion progresion;

  @override
  Widget build(BuildContext context) {
    final avance = progresion.avance;
    final siguiente = progresion.siguienteNivel;
    if (avance == null || siguiente == null) return const SizedBox.shrink();

    final tramo = siguiente.umbralExperiencia - progresion.inicioDelTramo;
    // Acotado al tramo: la experiencia no puede ser negativa, y si alguna vez
    // llegara un dato así, "-50 de 100 XP" confundiría más que ayudar. La
    // barra ya queda vacía, porque el avance viene acotado igual.
    final recorrido = (progresion.experiencia - progresion.inicioDelTramo)
        .clamp(0, tramo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$recorrido de $tramo XP',
                key: claveResumen,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              // Hacia abajo, no al redondeo más cercano: a falta de un punto
              // el redondeo diría 100% y el corredor leería que ya llegó.
              '${(avance * 100).floor()}%',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Para quien usa lector de pantalla, la barra sola no dice nada.
        Semantics(
          label:
              'Llevas $recorrido de $tramo puntos de experiencia hacia '
              '${siguiente.nombre}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              key: clave,
              value: avance,
              minHeight: 8,
              backgroundColor: AppColors.bgAlt,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
