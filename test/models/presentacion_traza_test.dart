import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/presentacion_traza.dart';

/// Pruebas del contenido de la presentación (SCRUM-278).
///
/// No comprueban la redacción —eso lo revisa el equipo—, sino que el contenido
/// cumpla lo que los criterios de SCRUM-277 piden decir, y que quepa donde se
/// va a mostrar.
void main() {
  test('dice qué es TRAZA nombrando entrenamientos, retos y niveles', () {
    // Criterio 2: las tres cosas que la app promete.
    expect(PresentacionTraza.queEs.toLowerCase(), contains('entrenamientos'));
    expect(PresentacionTraza.queEs.toLowerCase(), contains('retos'));
    expect(PresentacionTraza.queEs.toLowerCase(), contains('nivel'));
  });

  test('conserva el lema del prototipo', () {
    expect(PresentacionTraza.lema, 'Corre. Compite. Evoluciona.');
  });

  test('muestra las cinco funciones del criterio 3', () {
    expect(FuncionTraza.values, [
      FuncionTraza.registrar,
      FuncionTraza.retos,
      FuncionTraza.niveles,
      FuncionTraza.insignias,
      FuncionTraza.rutas,
    ]);
  });

  test('cada función se nombra y se explica', () {
    for (final funcion in FuncionTraza.values) {
      expect(funcion.titulo.trim(), isNotEmpty, reason: funcion.name);
      expect(funcion.detalle.trim(), isNotEmpty, reason: funcion.name);
    }
  });

  test('los textos caben en una tarjeta', () {
    // El título va en una línea y el detalle en dos: más largo se corta en un
    // teléfono estrecho.
    for (final funcion in FuncionTraza.values) {
      expect(
        funcion.titulo.length,
        lessThanOrEqualTo(30),
        reason: 'título largo en ${funcion.name}',
      );
      expect(
        funcion.detalle.length,
        lessThanOrEqualTo(90),
        reason: 'detalle largo en ${funcion.name}',
      );
    }
  });
}
