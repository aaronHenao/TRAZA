import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/ascenso.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/progresion.dart';

/// Pruebas de la subida automática de nivel (SCRUM-197, SCRUM-200,
/// SCRUM-201): un caso por criterio de aceptación de SCRUM-191.
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const oro = Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500);
  const niveles = [bronce, plata, oro];

  Ascenso? entre(int antes, int despues, [List<Nivel> lista = niveles]) =>
      Ascenso.entre(xpAntes: antes, xpDespues: despues, niveles: lista);

  test('1. con la XP exacta del umbral sube a ese nivel', () {
    final ascenso = entre(450, 500);

    expect(ascenso?.niveles, [plata]);
    expect(ascenso?.nivelFinal, plata);
  });

  test(
    '2. con XP de sobra sube, y lo que sobra es avance en el nuevo nivel',
    () {
      expect(entre(450, 700)?.nivelFinal, plata);

      // 200 de los 1000 que hay entre Plata y Oro.
      final progresion = Progresion.calcular(
        experiencia: 700,
        niveles: niveles,
      );
      expect(progresion.nivelActual, plata);
      expect(progresion.avance, 0.2);
    },
  );

  test('3. si cruza varios umbrales de una vez, los aplica todos y queda en '
      'el más alto', () {
    // Un reto grande: de Bronce a más allá de Oro.
    final ascenso = entre(120, 1600);

    expect(ascenso?.niveles, [plata, oro]);
    expect(ascenso?.nivelFinal, oro);
  });

  test('4. si la XP no alcanza el siguiente umbral no hay ascenso', () {
    expect(entre(120, 499), isNull);
    // La XP igual queda registrada: sigue en su nivel con más avance.
    expect(
      Progresion.calcular(experiencia: 499, niveles: niveles).nivelActual,
      bronce,
    );
  });

  test('6. en el último nivel la XP nueva no inventa un ascenso', () {
    expect(entre(1600, 5000), isNull);
  });

  test('sin nivel todavía, alcanzar el primer umbral es un ascenso', () {
    expect(entre(0, 100)?.nivelFinal, bronce);
  });

  test('sin XP nueva no hay ascenso', () {
    expect(entre(300, 300), isNull);
  });

  test('sin niveles creados no hay a dónde subir', () {
    expect(entre(0, 10000, const []), isNull);
  });

  test('no depende del orden en que lleguen los niveles', () {
    expect(entre(0, 600, const [oro, plata, bronce])?.niveles, [bronce, plata]);
  });
}
