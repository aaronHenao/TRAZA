import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servidor de tiles del mapa. OpenStreetMap: gratuito y sin API key.
///
/// Sus condiciones de uso piden identificar la app ([paqueteUserAgent])
/// y mostrar la atribución. Si TRAZA saliera a producción, aquí se
/// cambia la URL a un proveedor con plan gratuito (MapTiler, Stadia).
const String urlTilesOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Con esto se firma el `User-Agent` de cada petición de tile.
const String paqueteUserAgent = 'com.traza.traza';

/// Texto de atribución que OSM exige mostrar sobre el mapa.
const String atribucionOsm = '© OpenStreetMap contributors';

/// De dónde salen las imágenes de los tiles. La app descarga de la red;
/// las pruebas lo sobrescriben con un proveedor que no toca la red.
final proveedorTilesProvider =
    Provider<TileProvider>((ref) => NetworkTileProvider());
