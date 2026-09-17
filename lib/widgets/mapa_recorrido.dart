import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/punto_gps.dart';
import '../services/mapa_provider.dart';
import '../services/ubicacion_provider.dart';
import '../theme/traza_theme.dart';

/// Mapa con la posición actual del usuario (SCRUM-109).
///
/// Se dibuja cuando llega la primera lectura de [posicionEnVivoProvider]
/// y, a partir de ahí, mueve el marcador y centra la cámara en cada
/// lectura nueva. El trazo del recorrido es de otra HU: los puntos
/// registrados están en `recorridoProvider`.
class MapaRecorrido extends ConsumerStatefulWidget {
  const MapaRecorrido({super.key});

  /// Zoom de calle: suficiente para ver por qué cuadra va el usuario.
  static const double zoomInicial = 17;

  static const Key claveMarcador = Key('mapa-marcador');

  @override
  ConsumerState<MapaRecorrido> createState() => _MapaRecorridoState();
}

class _MapaRecorridoState extends ConsumerState<MapaRecorrido> {
  final _controlador = MapController();

  /// `MapController.move` solo funciona cuando el mapa ya está montado.
  bool _mapaListo = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _seguir(PuntoGps punto) {
    if (!_mapaListo) return;
    // Conserva el zoom que el usuario haya elegido con los dedos.
    _controlador.move(punto.aLatLng(), _controlador.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      final punto = siguiente.valueOrNull;
      if (punto != null) _seguir(punto);
    });

    final punto = ref.watch(posicionEnVivoProvider).valueOrNull;
    // Sin posición no hay dónde centrar: la nota de "buscando" que pone
    // MapaEntrenamiento encima cubre este hueco.
    if (punto == null) return const SizedBox.shrink();

    final tiles = ref.watch(proveedorTilesProvider);

    return FlutterMap(
      mapController: _controlador,
      options: MapOptions(
        initialCenter: punto.aLatLng(),
        initialZoom: MapaRecorrido.zoomInicial,
        backgroundColor: TrazaColors.trackingTop,
        // El mapa sigue al usuario: se puede acercar o alejar, pero no
        // arrastrar (la siguiente lectura lo volvería a centrar).
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
        ),
        // Más allá el servicio no tiene mapa que dar.
        maxZoom: zoomMaximoTiles,
        onMapReady: () => _mapaListo = true,
      ),
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(_matrizOscura),
          child: TileLayer(
            urlTemplate: urlTiles,
            userAgentPackageName: paqueteUserAgent,
            tileProvider: tiles,
            maxNativeZoom: zoomMaximoTiles.toInt(),
          ),
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: punto.aLatLng(),
              width: 26,
              height: 26,
              child: const _MarcadorPosicion(key: MapaRecorrido.claveMarcador),
            ),
          ],
        ),
        const _Atribucion(),
      ],
    );
  }
}

/// Oscurece los tiles claros de Esri para dejarlos como el fondo del
/// prototipo: pasa a escala de grises, invierte y baja un poco el brillo. Las
/// calles (blancas) quedan gris oscuro y el marcador lima resalta.
const List<double> _matrizOscura = [
  -0.85 * 0.2126, -0.85 * 0.7152, -0.85 * 0.0722, 0, 232, //
  -0.85 * 0.2126, -0.85 * 0.7152, -0.85 * 0.0722, 0, 228, //
  -0.85 * 0.2126, -0.85 * 0.7152, -0.85 * 0.0722, 0, 245, //
  0, 0, 0, 1, 0, //
];

/// El punto lima del prototipo (`#trackMarker`), con un halo suave.
class _MarcadorPosicion extends StatelessWidget {
  const _MarcadorPosicion({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TrazaColors.accent.withValues(alpha: 0.25),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TrazaColors.accent,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Atribución que exigen OpenStreetMap y CARTO, discreta sobre el mapa.
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
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

extension on PuntoGps {
  LatLng aLatLng() => LatLng(latitud, longitud);
}
