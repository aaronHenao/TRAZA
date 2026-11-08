import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/mapa_progresion.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_oficial.dart';

import '../utiles/rutas_repository_falso.dart';

/// Pruebas del modelo del mapa de progresión (rutas oficiales, etapa 2).
///
/// El mapa ya no es el camino de niveles por XP (SCRUM-226): es el camino de
/// rutas oficiales que armó el administrador. Cada parada está completada,
/// es la siguiente o está bloqueada, y todo sale del conjunto de rutas que el
/// corredor completó, no de una posición guardada.
void main() {
  final estadio = rutaDePrueba(
    id: 'ruta-estadio',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    distanciaKm: 5.23,
    dificultad: Dificultad.facil,
  );
  final nutibara = rutaDePrueba(
    id: 'ruta-nutibara',
    nombre: 'Cerro Nutibara',
    estado: EstadoRuta.publicada,
    distanciaKm: 7.5,
    dificultad: Dificultad.dificil,
  );
  final rio = rutaDePrueba(
    id: 'ruta-rio',
    nombre: 'Parque del río',
    estado: EstadoRuta.publicada,
    distanciaKm: 3,
  );

  /// Las rutas en el orden del camino: la primera es la posición 1.
  List<RutaOficial> enOrden(List<Ruta> rutas) => [
    for (final (i, ruta) in rutas.indexed)
      RutaOficial(posicion: i + 1, ruta: ruta),
  ];

  final camino = enOrden([estadio, nutibara, rio]);

  MapaProgresion con(Set<String> completadas, {List<RutaOficial>? oficiales}) =>
      MapaProgresion.calcular(
        oficiales: oficiales ?? camino,
        completadas: completadas,
      );

  List<String> ids(MapaProgresion mapa) => [
    for (final parada in mapa.paradas) parada.ruta.id,
  ];

  List<EstadoParada> estados(MapaProgresion mapa) => [
    for (final parada in mapa.paradas) parada.estado,
  ];

  group('criterio 1: las rutas oficiales en el orden del administrador', () {
    test('hay una parada por ruta oficial, por posición', () {
      expect(ids(con(const {})), ['ruta-estadio', 'ruta-nutibara', 'ruta-rio']);
    });

    test('el orden en que lleguen no cambia el camino: manda la posición', () {
      final desordenado = con(
        const {},
        oficiales: [
          RutaOficial(posicion: 3, ruta: rio),
          RutaOficial(posicion: 1, ruta: estadio),
          RutaOficial(posicion: 2, ruta: nutibara),
        ],
      );

      expect(ids(desordenado), ['ruta-estadio', 'ruta-nutibara', 'ruta-rio']);
      expect(desordenado.paradas.map((p) => p.oficial.posicion), [1, 2, 3]);
    });

    test('cada parada lleva su ruta oficial, con el nombre, la distancia y '
        'la dificultad que la pantalla muestra', () {
      final paradas = con(const {}).paradas;

      expect(paradas.first.oficial, camino.first);
      expect(paradas.first.ruta, same(estadio));
      expect(paradas.first.ruta.nombre, 'Vuelta al estadio');
      expect(paradas.first.ruta.distanciaKm, 5.23);
      expect(paradas.first.ruta.dificultad, Dificultad.facil);
      // Sin dificultad la ruta llega tal cual: la pantalla dice "Sin
      // clasificar".
      expect(paradas.last.ruta.dificultad, isNull);
    });
  });

  group('criterio 2: el estado de cada parada', () {
    test('sin ninguna completada, la primera es la siguiente y las demás '
        'están bloqueadas', () {
      // Es lo que verá todo el mundo en esta etapa: la tabla de
      // completadas todavía está vacía.
      expect(estados(con(const {})), [
        EstadoParada.siguiente,
        EstadoParada.bloqueada,
        EstadoParada.bloqueada,
      ]);
    });

    test('las completadas salen completadas, la primera que falta es la '
        'siguiente y las que vienen después, bloqueadas', () {
      expect(estados(con({'ruta-estadio'})), [
        EstadoParada.completada,
        EstadoParada.siguiente,
        EstadoParada.bloqueada,
      ]);
      expect(estados(con({'ruta-estadio', 'ruta-nutibara'})), [
        EstadoParada.completada,
        EstadoParada.completada,
        EstadoParada.siguiente,
      ]);
    });

    test('completadas todas, ninguna es siguiente ni bloqueada', () {
      expect(
        estados(con({'ruta-estadio', 'ruta-nutibara', 'ruta-rio'})),
        List.filled(3, EstadoParada.completada),
      );
    });

    test('nunca hay más de una siguiente', () {
      for (final completadas in <Set<String>>[
        {},
        {'ruta-estadio'},
        {'ruta-nutibara'},
        {'ruta-rio'},
        {'ruta-estadio', 'ruta-rio'},
        {'ruta-nutibara', 'ruta-rio'},
        {'ruta-estadio', 'ruta-nutibara', 'ruta-rio'},
      ]) {
        final siguientes = estados(
          con(completadas),
        ).where((estado) => estado == EstadoParada.siguiente);
        // Una mientras falte alguna; ninguna si las completó todas.
        final faltaAlguna = completadas.length < 3;
        expect(siguientes.length, faltaAlguna ? 1 : 0, reason: '$completadas');
      }
    });
  });

  group('criterio 3: dónde va el marcador "Tú"', () {
    test('sin ninguna completada, en la primera parada', () {
      final mapa = con(const {});

      expect(mapa.indiceActual, 0);
      expect(mapa.siguiente, mapa.paradas.first);
      expect(mapa.siguiente?.ruta.nombre, 'Vuelta al estadio');
      expect(mapa.totalCompletadas, 0);
      expect(mapa.caminoTerminado, isFalse);
    });

    test('en la parada siguiente, y cuenta las completadas', () {
      final mapa = con({'ruta-estadio'});

      expect(mapa.indiceActual, 1);
      expect(mapa.siguiente?.ruta.id, 'ruta-nutibara');
      expect(mapa.paradas[mapa.indiceActual!].estado, EstadoParada.siguiente);
      expect(mapa.totalCompletadas, 1);
      expect(mapa.caminoTerminado, isFalse);
      expect(mapa.hayRutas, isTrue);
    });

    test('justo antes del final, en la última, que todavía es la '
        'siguiente', () {
      final mapa = con({'ruta-estadio', 'ruta-nutibara'});

      expect(mapa.indiceActual, 2);
      expect(mapa.siguiente?.ruta.id, 'ruta-rio');
      expect(mapa.totalCompletadas, 2);
      expect(mapa.caminoTerminado, isFalse);
    });

    test('si las completó todas, en la última y con el camino terminado', () {
      final mapa = con({'ruta-estadio', 'ruta-nutibara', 'ruta-rio'});

      expect(mapa.indiceActual, 2);
      expect(mapa.siguiente, isNull);
      expect(mapa.totalCompletadas, 3);
      expect(mapa.caminoTerminado, isTrue);
    });

    test('con una sola ruta oficial, el marcador está en ella antes y '
        'después de completarla', () {
      final una = enOrden([estadio]);

      final antes = con(const {}, oficiales: una);
      expect(antes.indiceActual, 0);
      expect(estados(antes), [EstadoParada.siguiente]);
      expect(antes.caminoTerminado, isFalse);

      final despues = con({'ruta-estadio'}, oficiales: una);
      expect(despues.indiceActual, 0);
      expect(estados(despues), [EstadoParada.completada]);
      expect(despues.caminoTerminado, isTrue);
    });
  });

  group('criterio 4: una ruta completada fuera de orden', () {
    test('la 3 sin la 1 sale completada, pero el marcador sigue en la '
        'primera que falta', () {
      final mapa = con({'ruta-rio'});

      expect(estados(mapa), [
        EstadoParada.siguiente,
        EstadoParada.bloqueada,
        EstadoParada.completada,
      ]);
      expect(mapa.indiceActual, 0);
      expect(mapa.siguiente?.ruta.id, 'ruta-estadio');
      expect(mapa.totalCompletadas, 1);
      expect(mapa.caminoTerminado, isFalse);
    });

    test('con la 1 y la 3, la siguiente es la 2', () {
      final mapa = con({'ruta-estadio', 'ruta-rio'});

      expect(estados(mapa), [
        EstadoParada.completada,
        EstadoParada.siguiente,
        EstadoParada.completada,
      ]);
      expect(mapa.indiceActual, 1);
      expect(mapa.totalCompletadas, 2);
    });

    test('con todas menos la primera, el marcador no se mueve de ella', () {
      final mapa = con({'ruta-nutibara', 'ruta-rio'});

      expect(estados(mapa), [
        EstadoParada.siguiente,
        EstadoParada.completada,
        EstadoParada.completada,
      ]);
      expect(mapa.indiceActual, 0);
      expect(mapa.caminoTerminado, isFalse);
    });
  });

  group('criterio 5: sale de lo completado, no de posiciones guardadas', () {
    test('si el administrador reordena, el mapa se recalcula y nadie pierde '
        'lo corrido', () {
      final antes = con({'ruta-estadio'});
      expect(antes.siguiente?.ruta.id, 'ruta-nutibara');

      // El administrador sube el río al principio del camino.
      final despues = con({
        'ruta-estadio',
      }, oficiales: enOrden([rio, estadio, nutibara]));

      expect(ids(despues), ['ruta-rio', 'ruta-estadio', 'ruta-nutibara']);
      expect(estados(despues), [
        EstadoParada.siguiente,
        EstadoParada.completada,
        EstadoParada.bloqueada,
      ]);
      expect(despues.indiceActual, 0);
      expect(despues.totalCompletadas, antes.totalCompletadas);
    });

    test('las completadas que ya no son oficiales se ignoran en el '
        'conteo', () {
      final mapa = con({'ruta-estadio', 'ruta-retirada-del-mapa'});

      expect(mapa.paradas, hasLength(3));
      expect(ids(mapa), isNot(contains('ruta-retirada-del-mapa')));
      expect(mapa.totalCompletadas, 1);
      expect(mapa.siguiente?.ruta.id, 'ruta-nutibara');
    });

    test('una completada que ya no es oficial no da el camino por '
        'terminado', () {
      final mapa = con({
        'ruta-estadio',
        'ruta-nutibara',
        'ruta-retirada-del-mapa',
      });

      expect(mapa.totalCompletadas, 2);
      expect(mapa.caminoTerminado, isFalse);
      expect(mapa.siguiente?.ruta.id, 'ruta-rio');
    });

    test('con las oficiales completas y otras de más, cuenta solo las '
        'oficiales', () {
      final mapa = con({
        'ruta-estadio',
        'ruta-nutibara',
        'ruta-rio',
        'ruta-retirada-del-mapa',
      });

      expect(mapa.totalCompletadas, 3);
      expect(mapa.caminoTerminado, isTrue);
      expect(mapa.indiceActual, 2);
    });
  });

  group('criterio 7: sin rutas oficiales', () {
    test('no hay paradas ni lugar para el marcador', () {
      final mapa = con(const {}, oficiales: const []);

      expect(mapa.paradas, isEmpty);
      expect(mapa.indiceActual, isNull);
      expect(mapa.hayRutas, isFalse);
      expect(mapa.siguiente, isNull);
      expect(mapa.totalCompletadas, 0);
      // Sin camino no hay nada que terminar: no se felicita a nadie.
      expect(mapa.caminoTerminado, isFalse);
    });

    test('las completadas de antes no cuentan si ninguna sigue siendo '
        'oficial', () {
      final mapa = con({'ruta-estadio'}, oficiales: const []);

      expect(mapa.totalCompletadas, 0);
      expect(mapa.hayRutas, isFalse);
      expect(mapa.caminoTerminado, isFalse);
    });
  });

  group('ParadaMapa', () {
    test('dos paradas de la misma ruta oficial y el mismo estado son '
        'iguales', () {
      final a = ParadaMapa(
        oficial: camino.first,
        estado: EstadoParada.siguiente,
      );
      final b = ParadaMapa(
        oficial: RutaOficial(posicion: 1, ruta: estadio),
        estado: EstadoParada.siguiente,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('cambiar el estado la hace distinta', () {
      final a = ParadaMapa(
        oficial: camino.first,
        estado: EstadoParada.siguiente,
      );
      final b = ParadaMapa(
        oficial: camino.first,
        estado: EstadoParada.completada,
      );

      expect(a, isNot(b));
    });
  });

  group('MapaProgresion', () {
    test('dos mapas de las mismas rutas y completadas son iguales', () {
      final a = con({'ruta-estadio'});
      final b = con({'ruta-estadio'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('otra ruta completada lo hace distinto', () {
      expect(con({'ruta-estadio'}), isNot(con({'ruta-nutibara'})));
    });
  });
}
