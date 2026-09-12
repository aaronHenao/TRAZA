import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/ubicacion_provider.dart';
import '../theme/traza_theme.dart';
import 'mapa_recorrido.dart';

/// Contenedor del mapa de la pantalla de entrenamiento (SCRUM-102).
///
/// Observa la posición en vivo (SCRUM-108) para encender la píldora
/// "Ubicación en vivo" y avisar mientras no haya señal. Dentro va
/// [MapaRecorrido] (SCRUM-109), salvo que se pase otro [contenido].
class MapaEntrenamiento extends ConsumerWidget {
  const MapaEntrenamiento({super.key, this.contenido});

  /// Qué se dibuja en el hueco. Por defecto, el mapa real.
  final Widget? contenido;

  static const Key claveNota = Key('mapa-nota');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posicion = ref.watch(posicionEnVivoProvider);
    final enVivo = posicion.hasValue && !posicion.hasError;

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
            Positioned.fill(child: contenido ?? const MapaRecorrido()),
            // Igual que `.track-perm-note` del prototipo: cubre el mapa
            // mientras no se pueda mostrar la ubicación.
            if (!enVivo)
              Positioned.fill(
                child: _NotaUbicacion(
                  mensaje: posicion.hasError
                      ? 'No se pudo obtener tu ubicación.'
                      : 'Buscando tu ubicación...',
                ),
              ),
            Positioned(
              top: 14,
              left: 18,
              child: _PildoraEnVivo(activa: enVivo),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotaUbicacion extends StatelessWidget {
  const _NotaUbicacion({required this.mensaje});

  final String mensaje;

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
              mensaje,
              key: MapaEntrenamiento.claveNota,
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
  const _PildoraEnVivo({required this.activa});

  /// Con posición recibida el punto se enciende en lima; si no, apagado.
  final bool activa;

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
            decoration: BoxDecoration(
              color: activa
                  ? TrazaColors.accent
                  : Colors.white.withValues(alpha: 0.35),
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
