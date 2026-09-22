import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/tramo_recorrido.dart';
import 'package:traza/services/ventana_ritmo.dart';

/// Ritmo actual sobre los últimos segundos de recorrido (SCRUM-116).
void main() {
  final t0 = DateTime(2026, 1, 1, 8);

  TramoRecorrido tramo({
    required double metros,
    required int desde,
    required int hasta,
  }) => TramoRecorrido(
    metros: metros,
    inicio: t0.add(Duration(seconds: desde)),
    fin: t0.add(Duration(seconds: hasta)),
  );

  test('sin tramos no hay ritmo', () {
    final ventana = VentanaRitmo();

    expect(ventana.ritmoPorKm(t0), isNull);
    expect(ventana.ultimoMovimiento, isNull);
  });

  test('con poca distancia todavía no hay ritmo', () {
    final ventana = VentanaRitmo(distanciaMinimaMetros: 20);

    ventana.agregar(tramo(metros: 8, desde: 0, hasta: 5));

    expect(ventana.ritmoPorKm(t0.add(const Duration(seconds: 5))), isNull);
  });

  test('100 m en 30 s son 5\'00" por kilómetro', () {
    final ventana = VentanaRitmo();

    ventana.agregar(tramo(metros: 100, desde: 0, hasta: 30));

    expect(
      ventana.ritmoPorKm(t0.add(const Duration(seconds: 30))),
      const Duration(seconds: 300),
    );
  });

  test('parado dentro de la ventana el ritmo empeora sin puntos nuevos', () {
    final ventana = VentanaRitmo(duracion: const Duration(seconds: 60));

    ventana.agregar(tramo(metros: 100, desde: 0, hasta: 30));

    // Diez segundos después sigue sin moverse: los mismos 100 m, pero en
    // 40 s. El ritmo tiene que bajar ya, sin esperar al siguiente fix.
    expect(
      ventana.ritmoPorKm(t0.add(const Duration(seconds: 40))),
      const Duration(seconds: 400),
    );
  });

  test('pasada la ventana el recorrido viejo deja de contar', () {
    final ventana = VentanaRitmo(duracion: const Duration(seconds: 30));

    ventana.agregar(tramo(metros: 100, desde: 0, hasta: 30));

    // Un minuto quieto: ya no queda nada reciente que medir. Es lo que
    // evita el ritmo disparándose sin techo del promedio (SCRUM-116).
    expect(ventana.ritmoPorKm(t0.add(const Duration(seconds: 90))), isNull);
    expect(ventana.tramos, isEmpty);
  });

  test('solo cuenta lo que entra en la ventana', () {
    final ventana = VentanaRitmo(duracion: const Duration(seconds: 60));

    // Arrancó despacio y después apretó: el ritmo mostrado es el del
    // final, porque el tramo lento ya quedó fuera de la ventana.
    ventana.agregar(tramo(metros: 50, desde: 0, hasta: 20));
    ventana.agregar(tramo(metros: 200, desde: 60, hasta: 90));

    expect(
      ventana.ritmoPorKm(t0.add(const Duration(seconds: 90))),
      // Queda solo el segundo tramo: 200 m en 30 s → 150 s/km.
      const Duration(seconds: 150),
    );
  });

  test('el último movimiento es el fin del último tramo', () {
    final ventana = VentanaRitmo();

    ventana.agregar(tramo(metros: 100, desde: 0, hasta: 30));

    expect(ventana.ultimoMovimiento, t0.add(const Duration(seconds: 30)));
  });

  test('reiniciar olvida todo', () {
    final ventana = VentanaRitmo();

    ventana.agregar(tramo(metros: 100, desde: 0, hasta: 30));
    ventana.reiniciar();

    expect(ventana.ritmoPorKm(t0.add(const Duration(seconds: 30))), isNull);
    expect(ventana.ultimoMovimiento, isNull);
  });
}
