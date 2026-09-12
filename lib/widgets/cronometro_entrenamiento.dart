import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cronometro_provider.dart';
import '../theme/traza_theme.dart';

/// Cronómetro visible durante el entrenamiento (SCRUM-103 y SCRUM-106).
///
/// Solo pinta el tiempo que expone [cronometroProvider]; la cuenta la
/// lleva `CronometroService`.
class CronometroEntrenamiento extends ConsumerWidget {
  const CronometroEntrenamiento({super.key});

  /// Clave para localizar el texto del tiempo en las pruebas.
  static const Key claveTiempo = Key('cronometro-tiempo');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiempo = ref.watch(
      cronometroProvider.select((estado) => estado.tiempoFormateado),
    );
    final pausado = ref.watch(
      cronometroProvider.select((estado) => estado.estaPausado),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Tiempo transcurrido del entrenamiento',
            value: tiempo,
            liveRegion: true,
            child: Text(
              tiempo,
              key: claveTiempo,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.44,
                height: 1.2,
                // Ancho fijo por dígito: el cronómetro no "baila" al contar.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            // El prototipo muestra la etiqueta en mayúsculas sostenidas.
            pausado ? 'EN PAUSA' : 'TIEMPO',
            style: GoogleFonts.inter(
              color: pausado
                  ? TrazaColors.accent
                  : Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.66,
            ),
          ),
        ],
      ),
    );
  }
}
