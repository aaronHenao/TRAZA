import 'package:flutter_test/flutter_test.dart';
import 'package:traza/services/ventana_velocidad.dart';

/// Ritmo actual a partir de la velocidad de los últimos segundos
/// (SCRUM-116).
void main() {
  final t0 = DateTime(2026, 1, 1, 8);
  DateTime seg(int s) => t0.add(Duration(seconds: s));

  late VentanaVelocidad ventana;

  setUp(() => ventana = VentanaVelocidad());

  void muestras(List<double> velocidades, {int desde = 0}) {
    for (var i = 0; i < velocidades.length; i++) {
      ventana.agregar(velocidades[i], seg(desde + i));
    }
  }

  test('sin muestras no hay ritmo', () {
    expect(ventana.ritmoPorKm(t0), isNull);
  });

  test('el ritmo es el inverso de la velocidad media', () {
    muestras([2, 2, 2]);
    // 2 m/s → 500 s/km.
    expect(ventana.ritmoPorKm(seg(2)), const Duration(seconds: 500));
  });

  test('parado desde la última lectura: no hay ritmo', () {
    muestras([2, 2, 2, 0]);
    expect(ventana.ritmoPorKm(seg(3)), isNull);
  });

  test('una sola lectura en movimiento tras el reposo no basta', () {
    muestras([0, 0, 0, 1.4]);
    expect(ventana.ritmoPorKm(seg(3)), isNull);
  });

  test('al retomar no arrastra los segundos parados', () {
    muestras([0, 0, 0, 1.4, 1.4]);
    // 1.4 m/s → 714 s/km, sin promediar con los ceros.
    expect(ventana.ritmoPorKm(seg(4))!.inSeconds, (1000 / 1.4).floor());
  });

  test('sin lecturas nuevas el ritmo caduca con la ventana', () {
    muestras([2, 2, 2]);
    expect(ventana.ritmoPorKm(seg(5)), isNotNull);
    expect(ventana.ritmoPorKm(seg(20)), isNull);
  });

  test('sin lecturas nuevas el ritmo desaparece a los pocos segundos', () {
    muestras([2, 2, 2]);
    // Última muestra en el segundo 2; la vigencia es de 3 s.
    expect(ventana.ritmoPorKm(seg(5)), isNotNull);
    expect(ventana.ritmoPorKm(seg(6)), isNull);
  });

  test('al parar sin muestras nuevas no sube a saltos mientras caducan', () {
    // Caminando y, tras parar, solo lecturas sin velocidad fiable (no dejan
    // muestra): antes el ritmo cambiaba cada segundo mientras las viejas
    // salían de la ventana (BUG-001).
    ventana.agregar(2.0, seg(0));
    ventana.agregar(1.6, seg(1));
    ventana.agregar(1.2, seg(2));
    ventana.agregar(0.8, seg(3));
    for (var s = 7; s <= 13; s++) {
      expect(ventana.ritmoPorKm(seg(s)), isNull, reason: 'segundo $s');
    }
  });

  test('una muestra suelta que queda al caducar el reposo no da ritmo', () {
    // Caso del log en el teléfono (BUG-001): reposo, un paso y nada más.
    // Al salir el reposo de la ventana quedaba solo el paso y aparecía un
    // ritmo de 15'39" ocho segundos después.
    ventana.agregar(0, seg(0));
    ventana.agregar(1.06, seg(3));
    expect(ventana.ritmoPorKm(seg(3)), isNull);
    expect(ventana.ritmoPorKm(seg(11)), isNull);
  });

  test('reiniciar olvida todo', () {
    muestras([2, 2, 2]);
    ventana.reiniciar();
    expect(ventana.ritmoPorKm(seg(2)), isNull);
  });
}
