import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recorrido_local.dart';

/// Un recorrido guardado en el teléfono, tal como lo verá la pantalla de
/// sincronización (Drift, Desarrollo Móvil).
void main() {
  RecorridoLocal recorrido({
    String entrenamientoId = 'ent-1',
    String? usuarioId = 'uid-ana',
    DateTime? actualizadoEn,
    bool pendienteSync = true,
    String? ultimoError,
    bool rechazado = false,
    int puntosSinEnviar = 3,
  }) => RecorridoLocal(
    entrenamientoId: entrenamientoId,
    usuarioId: usuarioId,
    actualizadoEn: actualizadoEn ?? DateTime(2026, 11, 11, 8),
    pendienteSync: pendienteSync,
    ultimoError: ultimoError,
    rechazado: rechazado,
    puntosSinEnviar: puntosSinEnviar,
  );

  group('igualdad', () {
    test('dos recorridos con los mismos datos son iguales', () {
      expect(recorrido(), recorrido());
      expect(recorrido().hashCode, recorrido().hashCode);
    });

    for (final (campo, distinto) in [
      ('el entrenamiento', recorrido(entrenamientoId: 'ent-2')),
      ('el dueño', recorrido(usuarioId: 'uid-beto')),
      ('que no tenga dueño', recorrido(usuarioId: null)),
      ('la fecha', recorrido(actualizadoEn: DateTime(2026, 11, 11, 9))),
      ('si está pendiente', recorrido(pendienteSync: false)),
      (
        'el último error',
        recorrido(ultimoError: RecorridoLocal.motivoSinEnviar),
      ),
      ('si se rechazó', recorrido(rechazado: true)),
      ('los puntos sin enviar', recorrido(puntosSinEnviar: 4)),
    ]) {
      test('cambiar $campo los hace distintos', () {
        expect(distinto, isNot(recorrido()));
      });
    }
  });

  group('criterio 4: el motivo es un texto fijo, nunca el error crudo', () {
    test('el motivo del rechazo dice qué pasó sin detalles de la base', () {
      expect(
        RecorridoLocal.motivoRechazado,
        'La base no aceptó el recorrido: el entrenamiento ya no existe o es '
        'de otra cuenta.',
      );
    });

    test('el motivo de un envío fallido dice cuándo se reintenta', () {
      expect(
        RecorridoLocal.motivoSinEnviar,
        'No se pudo enviar. Se vuelve a intentar al abrir la app con '
        'conexión.',
      );
    });
  });
}
