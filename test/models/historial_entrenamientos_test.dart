import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/historial_entrenamientos.dart';
import 'package:traza/models/resumen_entrenamiento.dart';

/// Formato y validación del historial (SCRUM-126).
void main() {
  ResumenEntrenamiento entrenamiento({
    String id = 'e1',
    DateTime? fin,
    Duration duracion = const Duration(minutes: 28, seconds: 14),
    double? metros = 5100,
  }) => ResumenEntrenamiento(
    entrenamientoId: id,
    nombreActividad: 'Correr',
    fechaFin: fin ?? DateTime(2026, 9, 13, 7),
    duracion: duracion,
    distanciaMetros: metros,
  );

  group('detalleHistorial', () {
    test('distancia y tiempo, como el prototipo', () {
      expect(entrenamiento().detalleHistorial, '5.10 km · 00:28:14');
    });

    test('sin distancia calculada muestra solo el tiempo', () {
      expect(entrenamiento(metros: null).detalleHistorial, '00:28:14');
    });
  });

  group('prepararHistorial', () {
    test('ordena del más reciente al más antiguo', () {
      final viejo = entrenamiento(id: 'viejo', fin: DateTime(2026, 9, 1));
      final nuevo = entrenamiento(id: 'nuevo', fin: DateTime(2026, 9, 14));

      final lista = prepararHistorial([viejo, nuevo]);

      expect(lista.map((e) => e.entrenamientoId), ['nuevo', 'viejo']);
    });

    test('descarta filas incompletas y duraciones negativas', () {
      final lista = prepararHistorial([
        null,
        entrenamiento(id: 'malo', duracion: const Duration(seconds: -5)),
        entrenamiento(id: 'bueno'),
      ]);

      expect(lista.map((e) => e.entrenamientoId), ['bueno']);
    });

    test('quita repetidos por id', () {
      final lista = prepararHistorial([
        entrenamiento(id: 'e1'),
        entrenamiento(id: 'e1'),
      ]);

      expect(lista, hasLength(1));
    });
  });
}
