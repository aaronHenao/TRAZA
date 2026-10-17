import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/trazado.dart';

/// Pruebas de la forma del recorrido que dibuja el resumen (SCRUM-119).
void main() {
  PuntoGps punto(double latitud, double longitud) => PuntoGps(
    latitud: latitud,
    longitud: longitud,
    capturadoEn: DateTime(2026, 1, 1, 8),
  );

  void esperarPunto(Offset actual, double x, double y) {
    expect(actual.dx, closeTo(x, 1e-9), reason: 'x de $actual');
    expect(actual.dy, closeTo(y, 1e-9), reason: 'y de $actual');
  }

  test('sin puntos no hay trazado', () {
    final trazado = Trazado.desdePuntos(const []);

    expect(trazado.estaVacio, isTrue);
    expect(trazado.ancho, 0);
    expect(trazado.alto, 0);
  });

  test('conserva el orden de los puntos, de la partida a la llegada', () {
    // Sobre el ecuador un grado de longitud mide lo mismo que uno de latitud.
    final trazado = Trazado.desdePuntos([
      punto(0, 0),
      punto(0, 0.002),
      punto(0.001, 0.002),
    ]);

    expect(trazado.puntos, hasLength(3));
    // Sale del oeste, va al este y termina subiendo al norte.
    esperarPunto(trazado.puntos[0], 0, 0.5);
    esperarPunto(trazado.puntos[1], 1, 0.5);
    esperarPunto(trazado.puntos[2], 1, 0);
  });

  test('la dimensión más larga mide 1 y la otra conserva su proporción', () {
    final trazado = Trazado.desdePuntos([
      punto(0, 0),
      punto(0, 0.002),
      punto(0.001, 0.002),
    ]);

    expect(trazado.ancho, closeTo(1, 1e-9));
    expect(trazado.alto, closeTo(0.5, 1e-9));
  });

  test('corrige la longitud según la latitud para no estirar el recorrido', () {
    // A 60° de latitud un grado de longitud mide la mitad: 0.002° de ancho y
    // 0.001° de alto son, en metros, un cuadrado.
    final trazado = Trazado.desdePuntos([
      punto(60, 0),
      punto(60, 0.002),
      punto(60.001, 0.002),
    ]);

    expect(trazado.ancho, closeTo(1, 1e-3));
    expect(trazado.alto, closeTo(1, 1e-3));
  });

  test('el norte queda arriba', () {
    // De sur a norte, en Medellín.
    final trazado = Trazado.desdePuntos([
      punto(6.20, -75.6),
      punto(6.21, -75.6),
    ]);

    expect(trazado.ancho, 0);
    expect(trazado.alto, closeTo(1, 1e-9));
    esperarPunto(trazado.puntos.first, 0, 1);
    esperarPunto(trazado.puntos.last, 0, 0);
  });

  test('si el usuario no se movió, todo queda en un mismo punto', () {
    final trazado = Trazado.desdePuntos([
      punto(6.2311, -75.6105),
      punto(6.2311, -75.6105),
      punto(6.2311, -75.6105),
    ]);

    expect(trazado.estaVacio, isFalse);
    expect(trazado.puntos, List.filled(3, Offset.zero));
    expect(trazado.ancho, 0);
    expect(trazado.alto, 0);
  });

  test('con un solo punto no hay forma, pero sí un lugar', () {
    final trazado = Trazado.desdePuntos([punto(6.2311, -75.6105)]);

    expect(trazado.puntos, [Offset.zero]);
    expect(trazado.ancho, 0);
    expect(trazado.alto, 0);
  });

  test('dos trazados con los mismos puntos son iguales', () {
    Trazado crear() =>
        Trazado.desdePuntos([punto(6.20, -75.6), punto(6.21, -75.59)]);

    expect(crear(), crear());
    expect(crear().hashCode, crear().hashCode);
    expect(
      crear(),
      isNot(Trazado.desdePuntos([punto(6.20, -75.6), punto(6.22, -75.59)])),
    );
  });

  test('separa los puntos en tramos por las pausas (BUG-005)', () {
    final trazado = Trazado.desdePuntos(
      [punto(0, 0), punto(0, 0.001), punto(0, 0.003), punto(0, 0.004)],
      cortes: const [2],
    );

    expect(trazado.tramos, hasLength(2));
    esperarPunto(trazado.tramos[0].last, 0.25, 0);
    esperarPunto(trazado.tramos[1].first, 0.75, 0);
    // La partida y la llegada no cambian.
    esperarPunto(trazado.puntos.first, 0, 0);
    esperarPunto(trazado.puntos.last, 1, 0);
  });

  test('sin cortes es un solo tramo', () {
    final trazado = Trazado.desdePuntos([punto(0, 0), punto(0, 0.001)]);

    expect(trazado.tramos, hasLength(1));
  });

  test('los cortes cuentan para la igualdad', () {
    final puntos = [punto(0, 0), punto(0, 0.001)];

    expect(
      Trazado.desdePuntos(puntos, cortes: const [1]),
      isNot(Trazado.desdePuntos(puntos)),
    );
  });
}
