import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/mapa_progresion.dart';
import 'package:traza/models/nivel.dart';

/// Pruebas del modelo del mapa de progresión (SCRUM-226).
///
/// El mapa es el mismo dato que la progresión, pero puesto como un camino: una
/// parada inicial en 0 XP y luego una parada por cada nivel del administrador.
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const oro = Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500);
  const niveles = [bronce, plata, oro];

  MapaProgresion con(int experiencia, {List<Nivel> catalogo = niveles}) =>
      MapaProgresion.calcular(experiencia: experiencia, niveles: catalogo);

  group('el camino', () {
    test('empieza siempre por la parada inicial, en 0 XP y alcanzada', () {
      final inicio = con(700).paradas.first;

      expect(inicio.esInicio, isTrue);
      expect(inicio.nivelId, isNull);
      expect(inicio.nombre, 'Inicio');
      expect(inicio.umbralExperiencia, 0);
      expect(inicio.alcanzada, isTrue);
    });

    test('sigue con una parada por nivel, del umbral más bajo al más alto', () {
      final paradas = con(700).paradas;

      expect(paradas.map((p) => p.nombre), [
        'Inicio',
        'Bronce',
        'Plata',
        'Oro',
      ]);
      expect(paradas.map((p) => p.nivelId), [null, 'n-1', 'n-2', 'n-3']);
      expect(paradas.map((p) => p.umbralExperiencia), [0, 100, 500, 1500]);
      expect(paradas.skip(1).every((p) => !p.esInicio), isTrue);
    });

    test('el orden en que lleguen los niveles no cambia el camino', () {
      final desordenado = con(700, catalogo: const [oro, bronce, plata]);

      expect(desordenado.paradas.map((p) => p.nombre), [
        'Inicio',
        'Bronce',
        'Plata',
        'Oro',
      ]);
      expect(desordenado.indiceActual, 2);
      expect(desordenado.avanceEnTramo, closeTo(0.2, 0.0001));
    });

    test('marca alcanzadas las paradas hasta la actual y pendientes las '
        'demás', () {
      expect(con(700).paradas.map((p) => p.alcanzada), [
        true,
        true,
        true,
        false,
      ]);
      expect(con(0).paradas.map((p) => p.alcanzada), [
        true,
        false,
        false,
        false,
      ]);
    });

    test('guarda la experiencia tal cual se la dieron', () {
      expect(con(700).experiencia, 700);
    });
  });

  group('criterio 1: ubica al usuario en el camino', () {
    test('entre dos niveles, queda en el último alcanzado y avanza hacia el '
        'siguiente', () {
      final mapa = con(700);

      // Plata es la parada 2; de Plata (500) a Oro (1500) lleva 200 de 1000.
      expect(mapa.indiceActual, 2);
      expect(mapa.paradas[mapa.indiceActual].nombre, 'Plata');
      expect(mapa.avanceEnTramo, closeTo(0.2, 0.0001));
      expect(mapa.enUltimaParada, isFalse);
      expect(mapa.hayNiveles, isTrue);
    });

    test('antes del primer nivel, avanza desde el inicio hacia él', () {
      final mapa = con(25);

      expect(mapa.indiceActual, 0);
      expect(mapa.avanceEnTramo, closeTo(0.25, 0.0001));
    });
  });

  group('criterio 2: sin ningún avance', () {
    test(
      'con 0 XP queda en el punto inicial, al comienzo del primer tramo',
      () {
        final mapa = con(0);

        expect(mapa.indiceActual, 0);
        expect(mapa.paradas[mapa.indiceActual].esInicio, isTrue);
        expect(mapa.avanceEnTramo, 0);
        expect(mapa.enUltimaParada, isFalse);
      },
    );
  });

  group('al justo alcanzar un umbral', () {
    test('con la experiencia exacta ya está en esa parada y el tramo '
        'siguiente arranca en cero', () {
      final mapa = con(500);

      expect(mapa.indiceActual, 2);
      expect(mapa.paradas[2].alcanzada, isTrue);
      expect(mapa.avanceEnTramo, 0);
    });

    test('un punto antes todavía está en la parada anterior', () {
      final mapa = con(499);

      expect(mapa.indiceActual, 1);
      expect(mapa.paradas[2].alcanzada, isFalse);
      // De Bronce (100) a Plata (500): 399 de 400.
      expect(mapa.avanceEnTramo, closeTo(0.9975, 0.0001));
    });

    test('con la experiencia exacta del primer nivel ya lo alcanzó', () {
      final mapa = con(100);

      expect(mapa.indiceActual, 1);
      expect(mapa.avanceEnTramo, 0);
    });
  });

  group('en el nivel más alto', () {
    test('queda en la última parada, sin tramo por recorrer', () {
      final mapa = con(2000);

      expect(mapa.indiceActual, 3);
      expect(mapa.enUltimaParada, isTrue);
      expect(mapa.avanceEnTramo, isNull);
      expect(mapa.paradas.every((p) => p.alcanzada), isTrue);
    });

    test('con el umbral exacto del último nivel también', () {
      final mapa = con(1500);

      expect(mapa.indiceActual, 3);
      expect(mapa.enUltimaParada, isTrue);
      expect(mapa.avanceEnTramo, isNull);
    });
  });

  group('sin niveles configurados', () {
    test('el camino es solo la parada inicial y el usuario está ahí', () {
      final mapa = con(300, catalogo: const []);

      expect(mapa.paradas, [
        const ParadaMapa(
          nombre: 'Inicio',
          umbralExperiencia: 0,
          alcanzada: true,
        ),
      ]);
      expect(mapa.indiceActual, 0);
      expect(mapa.avanceEnTramo, isNull);
      expect(mapa.hayNiveles, isFalse);
      expect(mapa.enUltimaParada, isTrue);
      expect(mapa.experiencia, 300);
    });

    test('con 0 XP tampoco falla', () {
      final mapa = con(0, catalogo: const []);

      expect(mapa.indiceActual, 0);
      expect(mapa.hayNiveles, isFalse);
    });
  });

  group('ParadaMapa', () {
    test('dos paradas con los mismos datos son iguales', () {
      const a = ParadaMapa(
        nivelId: 'n-1',
        nombre: 'Bronce',
        umbralExperiencia: 100,
        alcanzada: true,
      );
      const b = ParadaMapa(
        nivelId: 'n-1',
        nombre: 'Bronce',
        umbralExperiencia: 100,
        alcanzada: true,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('cambiar si está alcanzada la hace distinta', () {
      const a = ParadaMapa(
        nivelId: 'n-1',
        nombre: 'Bronce',
        umbralExperiencia: 100,
        alcanzada: true,
      );
      const b = ParadaMapa(
        nivelId: 'n-1',
        nombre: 'Bronce',
        umbralExperiencia: 100,
        alcanzada: false,
      );

      expect(a, isNot(b));
    });
  });
}
