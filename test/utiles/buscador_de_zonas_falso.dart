import 'package:traza/models/zona.dart';
import 'package:traza/services/zonas_service.dart';

/// Un buscador de zonas en memoria para las pruebas (SCRUM-255): no sale a
/// la red y anota lo que se le preguntó.
class BuscadorDeZonasFalso implements BuscadorDeZonas {
  BuscadorDeZonasFalso({this.zonas = const {}});

  /// Lo que devuelve, por lo escrito en minúsculas. Lo demás no es un lugar.
  Map<String, Zona> zonas;

  /// Lo que lanza, si algo.
  Object? error;

  /// Cada pregunta: qué se escribió y desde dónde.
  final consultas = <({String texto, double? latitud, double? longitud})>[];

  @override
  Future<Zona?> buscar(
    String texto, {
    double? latitud,
    double? longitud,
  }) async {
    consultas.add((texto: texto, latitud: latitud, longitud: longitud));

    final error = this.error;
    if (error != null) throw error;

    return zonas[texto.toLowerCase()];
  }
}

/// Envigado, como lo devuelve Nominatim: con el límite real del municipio.
const envigado = Zona(
  nombre: 'Envigado',
  region: 'Antioquia',
  sur: 6.1003036,
  oeste: -75.6049283,
  norte: 6.1983821,
  este: -75.4741457,
);
