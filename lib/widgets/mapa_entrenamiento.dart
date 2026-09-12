import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/punto_gps.dart';
import '../services/ubicacion_provider.dart';
import '../theme/traza_theme.dart';

/// Contenedor del mapa de la pantalla de entrenamiento (SCRUM-102).
///
/// Observa la posición en vivo (SCRUM-108) para encender la píldora
/// "Ubicación en vivo" y avisar mientras no haya señal. El mapa en sí lo
/// dibuja SCRUM-109 pasando su widget por [contenido]; mientras no
/// exista, el hueco muestra la última posición como texto para poder
/// verificar la captura.
class MapaEntrenamiento extends ConsumerWidget {
  const MapaEntrenamiento({super.key, this.contenido});

  /// Widget que dibuja el mapa. Mientras no exista, se muestra el
  /// estado vacío.
  final Widget? contenido;

  static const Key claveNota = Key('mapa-nota');
  static const Key claveCoordenadas = Key('mapa-coordenadas');

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
            Positioned.fill(
              child: contenido ?? _MapaVacio(posicion: posicion.valueOrNull),
            ),
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

/// Hueco del mapa hasta que SCRUM-109 lo dibuje. Provisional: enseña la
/// última lectura para que se pueda comprobar que el rastreo funciona.
class _MapaVacio extends StatelessWidget {
  const _MapaVacio({required this.posicion});

  final PuntoGps? posicion;

  @override
  Widget build(BuildContext context) {
    final punto = posicion;
    if (punto == null) return const SizedBox.shrink();

    final precision = punto.precisionMetros;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.my_location_rounded,
            size: 30,
            color: TrazaColors.accent,
          ),
          const SizedBox(height: 10),
          Text(
            '${punto.latitud.toStringAsFixed(5)}, '
            '${punto.longitud.toStringAsFixed(5)}',
            key: MapaEntrenamiento.claveCoordenadas,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (precision != null)
            Text(
              '± ${precision.round()} m',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
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
