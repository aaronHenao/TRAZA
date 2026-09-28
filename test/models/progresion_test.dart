import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/progresion.dart';

/// Pruebas del modelo de progresión del corredor (SCRUM-185).
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const oro = Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500);
  const niveles = [bronce, plata, oro];

  Progresion con(int experiencia, {List<Nivel> catalogo = niveles}) =>
      Progresion.calcular(experiencia: experiencia, niveles: catalogo);

  group('en medio de la progresión', () {
    test('sitúa al corredor entre el nivel alcanzado y el siguiente', () {
      final progresion = con(700);

      expect(progresion.nivelActual, plata);
      expect(progresion.siguienteNivel, oro);
      expect(progresion.experiencia, 700);
    });

    test('dice cuánta experiencia falta para el siguiente', () {
      expect(con(700).experienciaFaltante, 800);
    });

    test('el tramo se mide desde el umbral del nivel actual', () {
      // De Plata (500) a Oro (1500) hay 1000; con 700 lleva 200 recorridos.
      expect(con(700).avance, closeTo(0.2, 0.0001));
    });

    test('el orden en que lleguen los niveles no cambia el resultado', () {
      final desordenados = con(700, catalogo: const [oro, bronce, plata]);

      expect(desordenados.nivelActual, plata);
      expect(desordenados.siguienteNivel, oro);
    });
  });

  group('al justo alcanzar un umbral', () {
    test('con la experiencia exacta ya se está en ese nivel', () {
      final progresion = con(500);

      expect(progresion.nivelActual, plata);
      expect(progresion.siguienteNivel, oro);
      // Recién llegado: el tramo nuevo arranca de cero.
      expect(progresion.avance, 0);
    });

    test('un punto antes todavía es el nivel anterior', () {
      final progresion = con(499);

      expect(progresion.nivelActual, bronce);
      expect(progresion.siguienteNivel, plata);
      expect(progresion.experienciaFaltante, 1);
    });
  });

  group('antes del primer nivel', () {
    test('sin experiencia suficiente aún no hay nivel alcanzado', () {
      final progresion = con(40);

      expect(progresion.nivelActual, isNull);
      expect(progresion.siguienteNivel, bronce);
      expect(progresion.experienciaFaltante, 60);
      expect(progresion.hayNiveles, isTrue);
    });

    test('el primer tramo se cuenta desde cero', () {
      expect(con(40).inicioDelTramo, 0);
      expect(con(40).avance, closeTo(0.4, 0.0001));
    });

    test('sin nada de experiencia el avance es cero, no un error', () {
      expect(con(0).avance, 0);
      expect(con(0).nivelActual, isNull);
    });
  });

  group('en el nivel más alto', () {
    test('no inventa un siguiente nivel', () {
      final progresion = con(2000);

      expect(progresion.nivelActual, oro);
      expect(progresion.siguienteNivel, isNull);
      expect(progresion.enNivelMaximo, isTrue);
    });

    test('no hay experiencia faltante ni barra que llenar', () {
      expect(con(2000).experienciaFaltante, isNull);
      expect(con(2000).avance, isNull);
    });
  });

  group('sin niveles configurados', () {
    test('no revienta: simplemente no hay progresión que mostrar', () {
      final progresion = con(700, catalogo: const []);

      expect(progresion.hayNiveles, isFalse);
      expect(progresion.nivelActual, isNull);
      expect(progresion.siguienteNivel, isNull);
      expect(progresion.experienciaFaltante, isNull);
      expect(progresion.avance, isNull);
      // La experiencia sigue siendo la suya, aunque no haya dónde ubicarla.
      expect(progresion.experiencia, 700);
    });

    test('estar sin niveles no es estar en el nivel máximo', () {
      expect(con(700, catalogo: const []).enNivelMaximo, isFalse);
    });
  });

  group('cuando gana experiencia', () {
    test('refleja el valor nuevo sin recalcularlo por su cuenta', () {
      // Criterio 5: la XP se la dan hecha; la progresión solo la ubica.
      expect(con(450).nivelActual, bronce);
      expect(con(520).nivelActual, plata);
      expect(con(520).experiencia, 520);
    });

    test('con un solo nivel se entra en él y no queda nada por delante', () {
      final progresion = con(150, catalogo: const [bronce]);

      expect(progresion.nivelActual, bronce);
      expect(progresion.enNivelMaximo, isTrue);
    });
  });

  test('dos progresiones con los mismos datos son iguales', () {
    expect(con(700), con(700));
    expect(con(700).hashCode, con(700).hashCode);
    expect(con(700), isNot(con(800)));
  });
}
