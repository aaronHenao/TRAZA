import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/filtros_rutas.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/models/ruta.dart';

import '../utiles/rutas_repository_falso.dart';

/// Pruebas de los filtros de Explorar rutas (SCRUM-274 y SCRUM-275).
void main() {
  final facilCorta = rutaDePrueba(
    id: 'facil-corta',
    distanciaKm: 3.2,
    dificultad: Dificultad.facil,
  );
  final facilLarga = rutaDePrueba(
    id: 'facil-larga',
    distanciaKm: 15,
    dificultad: Dificultad.facil,
  );
  final moderadaMedia = rutaDePrueba(
    id: 'moderada-media',
    distanciaKm: 7.5,
    dificultad: Dificultad.moderada,
  );
  final sinClasificar = rutaDePrueba(id: 'sin-clasificar', distanciaKm: 4.1);
  final sinDistancia = rutaDePrueba(
    id: 'sin-distancia',
    distanciaKm: null,
    dificultad: Dificultad.facil,
  );
  final rutas = [
    facilCorta,
    facilLarga,
    moderadaMedia,
    sinClasificar,
    sinDistancia,
  ];

  List<String> ids(List<Ruta> rutas) => [for (final ruta in rutas) ruta.id];

  test('sin nada elegido deja la lista como estaba, también las que no '
      'tienen distancia ni dificultad', () {
    const filtros = FiltrosRutas();

    expect(filtros.ninguno, isTrue);
    expect(filtros.cuantos, 0);
    expect(filtros.aplicar(rutas), same(rutas));
  });

  group('con la distancia (SCRUM-274)', () {
    test('solo las que entran en el rango, en el orden en que venían', () {
      const filtros = FiltrosRutas(distancia: RangoDistancia.menosDe5);

      expect(ids(filtros.aplicar(rutas)), ['facil-corta', 'sin-clasificar']);
    });

    test('una sin distancia registrada no sale con ningún rango', () {
      for (final rango in RangoDistancia.values) {
        expect(
          ids(FiltrosRutas(distancia: rango).aplicar(rutas)),
          isNot(contains('sin-distancia')),
          reason: rango.etiqueta,
        );
      }
    });
  });

  group('con la dificultad', () {
    test('solo las de esa dificultad, en el orden en que venían', () {
      const filtros = FiltrosRutas(dificultad: Dificultad.facil);

      expect(ids(filtros.aplicar(rutas)), [
        'facil-corta',
        'facil-larga',
        'sin-distancia',
      ]);
    });

    test('una sin clasificar no sale con ninguna dificultad', () {
      for (final dificultad in Dificultad.values) {
        expect(
          ids(FiltrosRutas(dificultad: dificultad).aplicar(rutas)),
          isNot(contains('sin-clasificar')),
          reason: dificultad.etiqueta,
        );
      }
    });
  });

  group('con las dos (SCRUM-275, criterio 3 de HU-37)', () {
    test('solo las que cumplen las dos a la vez', () {
      const filtros = FiltrosRutas(
        dificultad: Dificultad.facil,
        distancia: RangoDistancia.menosDe5,
      );

      expect(filtros.cuantos, 2);
      // La fácil de 15 km y la corta sin clasificar cumplen una sola.
      expect(ids(filtros.aplicar(rutas)), ['facil-corta']);
    });

    test('si ninguna cumple las dos, la lista queda vacía aunque cada una '
        'por separado tenga rutas', () {
      const filtros = FiltrosRutas(
        dificultad: Dificultad.moderada,
        distancia: RangoDistancia.menosDe5,
      );

      expect(filtros.aplicar(rutas), isEmpty);
      expect(
        const FiltrosRutas(dificultad: Dificultad.moderada).aplicar(rutas),
        isNotEmpty,
      );
      expect(
        const FiltrosRutas(distancia: RangoDistancia.menosDe5).aplicar(rutas),
        isNotEmpty,
      );
    });
  });

  test('dos filtros con lo mismo elegido son iguales', () {
    expect(
      const FiltrosRutas(
        dificultad: Dificultad.facil,
        distancia: RangoDistancia.de5a10,
      ),
      const FiltrosRutas(
        dificultad: Dificultad.facil,
        distancia: RangoDistancia.de5a10,
      ),
    );
    expect(
      const FiltrosRutas(dificultad: Dificultad.facil),
      isNot(const FiltrosRutas(distancia: RangoDistancia.menosDe5)),
    );
  });
}
