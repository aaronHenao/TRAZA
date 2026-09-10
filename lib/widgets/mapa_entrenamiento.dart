import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/traza_theme.dart';

/// Contenedor del mapa de la pantalla de entrenamiento (SCRUM-102).
///
/// Es solo el marco visual: la ubicación en vivo y el trazado del
/// recorrido los implementa SCRUM-41 sobre este mismo hueco, pasando su
/// `GoogleMap` (u otro widget) por [contenido].
class MapaEntrenamiento extends StatelessWidget {
  const MapaEntrenamiento({super.key, this.contenido});

  /// Widget que dibuja el mapa. Mientras no exista, se muestra el
  /// estado vacío.
  final Widget? contenido;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: contenido ?? const _MapaVacio()),
            const Positioned(top: 14, left: 18, child: _PildoraEnVivo()),
          ],
        ),
      ),
    );
  }
}

class _MapaVacio extends StatelessWidget {
  const _MapaVacio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 30,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Aquí se mostrará tu recorrido en el mapa.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PildoraEnVivo extends StatelessWidget {
  const _PildoraEnVivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: TrazaColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Ubicación en vivo',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
