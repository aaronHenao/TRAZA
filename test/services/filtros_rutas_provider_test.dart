import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/filtros_rutas_provider.dart';

import '../utiles/rutas_repository_falso.dart';

/// Pruebas de filtrar las rutas de Explorar rutas (SCRUM-274).
void main() {
  final corta = rutaDePrueba(id: 'corta', distanciaKm: 3.2);
  final media = rutaDePrueba(id: 'media', distanciaKm: 7.5);
  final sinDistancia = rutaDePrueba(id: 'sin-distancia', distanciaKm: null);
  final otraCorta = rutaDePrueba(id: 'otra-corta', distanciaKm: 4.1);
  final rutas = [corta, media, sinDistancia, otraCorta];

  List<String> ids(List<Ruta> rutas) => [for (final ruta in rutas) ruta.id];

  test('sin rango deja la lista como estaba, también las que no tienen '
      'distancia', () {
    expect(filtrarRutas(rutas), same(rutas));
  });

  test('con un rango, solo las que entran, en el orden en que venían', () {
    expect(ids(filtrarRutas(rutas, distancia: RangoDistancia.menosDe5)), [
      'corta',
      'otra-corta',
    ]);
    expect(ids(filtrarRutas(rutas, distancia: RangoDistancia.de5a10)), [
      'media',
    ]);
  });

  test('si ninguna entra, la lista queda vacía', () {
    expect(filtrarRutas(rutas, distancia: RangoDistancia.masDe20), isEmpty);
  });

  test('una ruta sin distancia registrada no sale con ningún rango', () {
    for (final rango in RangoDistancia.values) {
      expect(
        ids(filtrarRutas(rutas, distancia: rango)),
        isNot(contains('sin-distancia')),
        reason: rango.etiqueta,
      );
    }
  });
}
