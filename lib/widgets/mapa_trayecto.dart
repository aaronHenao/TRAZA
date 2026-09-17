import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/punto_gps.dart';
import '../services/mapa_provider.dart';
import '../theme/app_colors.dart';
import '../theme/traza_theme.dart';

/// Mapa con el trayecto completo de un entrenamiento (SCRUM-120).
///
/// Dibuja la línea de los puntos guardados sobre las calles, marca la partida
/// (blanco) y la llegada (lima) y encuadra la cámara en todo el recorrido. Usa
/// los mismos tiles y el mismo tono oscuro que el mapa del entrenamiento en
/// curso (`MapaRecorrido`).
class MapaTrayecto extends ConsumerWidget {
  const MapaTrayecto({required this.puntos, super.key})
    : assert(puntos.length > 0, 'Sin puntos no hay trayecto que mostrar');

  /// Puntos del recorrido en orden de captura.
  final List<PuntoGps> puntos;

  /// Zoom de calle: al que se muestra un recorrido de un solo lugar y el
  /// máximo al que llega el encuadre, para no pegarse demasiado a una ruta
  /// corta.
  static const zoomCercano = 17.0;

  /// Espacio libre alrededor del recorrido al encuadrarlo, para que la
  /// partida y la llegada no queden pegadas al borde.
  static const margenEncuadre = EdgeInsets.all(48);

  static const grosorLinea = 4.0;

  static const clavePartida = Key('trayecto-partida');
  static const claveLlegada = Key('trayecto-llegada');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordenadas = [
      for (final punto in puntos) LatLng(punto.latitud, punto.longitud),
    ];
    // Si todos los puntos caen en el mismo lugar no hay forma que encuadrar
    // ni línea que dibujar.
    final hayForma = coordenadas.toSet().length > 1;

    return FlutterMap(
      options: MapOptions(
        backgroundColor: TrazaColors.trackingTop,
        initialCenter: coordenadas.first,
        initialZoom: zoomCercano,
        initialCameraFit: hayForma
            ? CameraFit.coordinates(
                coordinates: coordenadas,
                padding: margenEncuadre,
                maxZoom: zoomCercano,
              )
            : null,
        // Más allá el servicio no tiene mapa que dar.
        maxZoom: zoomMaximoTiles,
        // Se puede mover y acercar para revisar la ruta; girarla no aporta.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(_matrizOscura),
          child: TileLayer(
            urlTemplate: urlTiles,
            userAgentPackageName: paqueteUserAgent,
            tileProvider: ref.watch(proveedorTilesProvider),
            maxNativeZoom: zoomMaximoTiles.toInt(),
          ),
        ),
        if (hayForma)
          PolylineLayer(
            polylines: [
              Polyline(
                points: coordenadas,
                color: AppColors.accent,
                strokeWidth: grosorLinea,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: coordenadas.first,
              width: 18,
              height: 18,
              child: const _Extremo(key: clavePartida, color: Colors.white),
            ),
            Marker(
              point: coordenadas.last,
              width: 18,
              height: 18,
              child: const _Extremo(key: claveLlegada, color: AppColors.accent),
            ),
          ],
        ),
        const _Atribucion(),
      ],
    );
  }
}

/// El mismo tono oscuro que `MapaRecorrido` le da a los tiles claros de Esri:
/// escala de grises, invertida y con un poco menos de brillo. Si allá cambia,
/// conviene cambiarlo aquí también.
const List<double> _matrizOscura = [
  -0.85 * 0.2126, -0.85 * 0.7152, -0.85 * 0.0722, 0, 232, //
  -0.85 * 0.2126, -0.85 * 0.7152, -0.85 * 0.0722, 0, 228, //
  -0.85 * 0.2126, -0.85 * 0.7152, -0.85 * 0.0722, 0, 245, //
  0, 0, 0, 1, 0, //
];

/// Punto de partida o de llegada, con borde oscuro para que resalte sobre la
/// línea.
class _Extremo extends StatelessWidget {
  const _Extremo({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: TrazaColors.trackingTop, width: 3),
      ),
    );
  }
}

/// Atribución que exige el servicio de mapas, discreta sobre el mapa.
class _Atribucion extends StatelessWidget {
  const _Atribucion();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: TrazaColors.trackingTop.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          atribucionMapa,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
