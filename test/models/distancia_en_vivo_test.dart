import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/distancia_en_vivo.dart';

void main() {
  group('kilometros', () {
    test('0 m → "0.00 km"', () {
      expect(const DistanciaEnVivo().kilometros, '0.00 km');
    });

    test('2843.7 m → "2.84 km"', () {
      expect(const DistanciaEnVivo(metros: 2843.7).kilometros, '2.84 km');
    });

    test('2845 m redondea a "2.85 km"', () {
      expect(const DistanciaEnVivo(metros: 2845).kilometros, '2.85 km');
    });

    test('12345 m → "12.35 km"', () {
      expect(const DistanciaEnVivo(metros: 12345).kilometros, '12.35 km');
    });
  });

  group('ritmoPara', () {
    test('sin distancia suficiente es 0\'00"', () {
      expect(
        const DistanciaEnVivo().ritmoPara(const Duration(minutes: 5)),
        "0'00\"",
      );
      expect(
        const DistanciaEnVivo(
          metros: 9.9,
        ).ritmoPara(const Duration(minutes: 5)),
        "0'00\"",
      );
    });

    test('1 km en 6 min 10 s → 6\'10"', () {
      expect(
        const DistanciaEnVivo(
          metros: 1000,
        ).ritmoPara(const Duration(minutes: 6, seconds: 10)),
        "6'10\"",
      );
    });

    test('5 km en 30 min → 6\'00"', () {
      expect(
        const DistanciaEnVivo(
          metros: 5000,
        ).ritmoPara(const Duration(minutes: 30)),
        "6'00\"",
      );
    });

    test('redondea los segundos antes de separar minutos', () {
      // 5'59.9" debe quedar en 6'00" y no en 5'60".
      expect(
        const DistanciaEnVivo(
          metros: 1000,
        ).ritmoPara(const Duration(minutes: 5, seconds: 59, milliseconds: 900)),
        "6'00\"",
      );
    });

    test('igual que el resumen: misma distancia y tiempo, mismo ritmo', () {
      // El resumen formatea `6'10"/km`; en vivo se omite el sufijo porque
      // la etiqueta de la casilla ya dice "RITMO /KM".
      expect(
        const DistanciaEnVivo(
          metros: 2500,
        ).ritmoPara(const Duration(minutes: 15)),
        "6'00\"",
      );
    });
  });

  test('igualdad por valor', () {
    expect(const DistanciaEnVivo(metros: 5), const DistanciaEnVivo(metros: 5));
    expect(
      const DistanciaEnVivo(metros: 5),
      isNot(const DistanciaEnVivo(metros: 6)),
    );
  });
}
