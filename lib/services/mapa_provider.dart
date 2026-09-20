import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servidor de tiles del mapa: Esri World Street Map, sin API key.
///
/// Ojo con el orden de la URL: Esri pide `{z}/{y}/{x}`, no `{z}/{x}/{y}`.
///
/// Por qué este y no otros, comprobado pidiendo tiles de Medellín:
/// - `tile.openstreetmap.org` responde imágenes vacías (HTTP 200 de 103
///   bytes) a las apps: su política de uso las excluye. El mapa se veía negro.
/// - CARTO estampa "API KEY REQUIRED" sobre cada tile si no hay cuenta.
/// - Esri Dark Gray Canvas, que vendría oscuro de fábrica, solo llega al
///   zoom 16 en la ciudad; del 17 en adelante devuelve "Map data not yet
///   available".
///
/// Si algún día también dejara de servir, la alternativa es una cuenta
/// gratuita (MapTiler, Stadia): se cambia esta URL y se añade la key.
const String urlTiles =
    'https://server.arcgisonline.com/ArcGIS/rest/services/'
    'World_Street_Map/MapServer/tile/{z}/{y}/{x}';

/// Hasta dónde hay tiles. Más allá, el servicio responde "Map data not yet
/// available" en vez de un mapa.
const double zoomMaximoTiles = 18;

/// Con esto se firma el `User-Agent` de cada petición de tile.
const String paqueteUserAgent = 'com.traza.traza';

/// Atribución que hay que mostrar sobre el mapa, resumida de la que declara
/// el servicio en su `copyrightText`.
const String atribucionMapa = '© Esri, HERE, Garmin, © OpenStreetMap';

/// De dónde salen las imágenes de los tiles. La app descarga de la red; las
/// pruebas lo sobrescriben con un proveedor que no toca la red.
final proveedorTilesProvider =
    Provider<TileProvider>((ref) => NetworkTileProvider());
