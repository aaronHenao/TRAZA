import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../models/punto_gps.dart';
import '../services/cronometro_provider.dart';
import '../services/mapa_provider.dart';
import '../services/recorrido_provider.dart';
import '../services/ubicacion_provider.dart';
import '../theme/traza_theme.dart';

/// Mapa con la posición actual del usuario y el trazo recorrido
/// (SCRUM-109 y SCRUM-116).
///
/// Se dibuja cuando llega la primera lectura de [posicionEnVivoProvider].
/// El marcador y la cámara siguen al último punto del recorrido
/// ([recorridoProvider]), no a cada lectura cruda: el recorrido solo avanza
/// con movimiento real, así que con el usuario quieto el marcador no baila
/// con el ruido del GPS, y lo que se ve en el mapa coincide con los
/// kilómetros. En pausa, o mientras no haya recorrido, se usa la lectura
/// cruda.
class MapaRecorrido extends ConsumerStatefulWidget {
  const MapaRecorrido({super.key});

  /// Zoom de calle: suficiente para ver por qué cuadra va el usuario.
  static const double zoomInicial = 17;

  static const Key claveMarcador = Key('mapa-marcador');

  /// Grosor del trazo, el mismo `stroke-width` del `#trackPath` del
  /// prototipo.
  static const double grosorTrazo = 3.5;

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
    if (!_mapaListo || !mounted) return;
    // Conserva el zoom que el usuario haya elegido con los dedos.
    _controlador.move(punto.aLatLng(), _controlador.camera.zoom);
  }

  /// Con la actividad en curso el marcador va con el trazo; en pausa (o
  /// antes de arrancar) muestra dónde está el usuario de verdad.
  bool _sigueTrazo() =>
      ref.read(cronometroProvider).estaEnCurso &&
      ref.read(recorridoProvider).puntos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final lectura = ref.watch(posicionEnVivoProvider).valueOrNull;
    // Se observa desde el principio, antes de tener posición, para que el
    // registro esté escuchando cuando llegue el primer fix y el trazo
    // arranque en ese punto y no en el segundo.
    final recorrido = ref.watch(recorridoProvider);
    final trazo = recorrido.puntos;
    final enCurso = ref.watch(
      cronometroProvider.select((estado) => estado.estaEnCurso),
    );
    final punto = enCurso && trazo.isNotEmpty ? trazo.last : lectura;

    ref.listen(recorridoProvider.select((r) => r.ultimo), (_, ultimo) {
      if (ultimo != null && _sigueTrazo()) _seguir(ultimo);
    });
    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      final lectura = siguiente.valueOrNull;
      if (lectura != null && !_sigueTrazo()) _seguir(lectura);
    });

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
        // Con un solo punto no hay línea que dibujar; la capa lo tolera,
        // pero no vale la pena montarla.
        if (trazo.length >= 2)
          PolylineLayer(
            // Una línea por tramo: lo recorrido en pausa no se dibuja
            // (BUG-005).
            polylines: [
              for (final tramo in recorrido.tramos)
                if (tramo.length >= 2)
                  Polyline(
                    points: [for (final punto in tramo) punto.aLatLng()],
                    color: TrazaColors.accent,
                    strokeWidth: MapaRecorrido.grosorTrazo,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
            ],
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
