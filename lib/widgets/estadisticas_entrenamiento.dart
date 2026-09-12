import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fila de métricas de la pantalla de entrenamiento (SCRUM-102).
///
/// Componente **sin lógica**: los valores llegan ya formateados desde
/// afuera. La distancia recorrida y el ritmo los calcula la HU que les
/// corresponde; aquí solo se reservan sus casillas.
class EstadisticasEntrenamiento extends StatelessWidget {
  const EstadisticasEntrenamiento({
    super.key,
    this.distancia = '0.00 km',
    this.ritmo = "0'00\"",
  });

  final String distancia;
  final String ritmo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Row(
        children: [
          Expanded(
            child: _Metrica(valor: distancia, etiqueta: 'DISTANCIA'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metrica(valor: ritmo, etiqueta: 'RITMO /KM'),
          ),
        ],
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          valor,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.42,
          ),
        ),
      ],
    );
  }
}
