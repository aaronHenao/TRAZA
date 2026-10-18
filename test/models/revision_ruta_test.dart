import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/revision_ruta.dart';
import 'package:traza/models/ruta.dart';

/// Las reglas de la revisión de rutas en dos etapas (SCRUM-321).
void main() {
  group('EtapaRevision', () {
    test('el administrador revisa lo recien enviado', () {
      expect(
        EtapaRevision.administrador.estadoPendiente,
        EstadoRuta.enRevision,
      );
    });

    test('el Runner Experto revisa lo que el administrador aprobo', () {
      expect(EtapaRevision.experto.estadoPendiente, EstadoRuta.revisionExperto);
    });
  });

  group('etiquetas de los estados', () {
    test('son los textos de la HU', () {
      expect(
        EstadoRuta.enRevision.etiqueta,
        'Pendiente de revisión del administrador',
      );
      expect(
        EstadoRuta.revisionExperto.etiqueta,
        'Pendiente de revisión del Runner Experto',
      );
      expect(EstadoRuta.publicada.etiqueta, 'Publicada');
      expect(EstadoRuta.rechazada.etiqueta, 'Rechazada');
    });

    test('solo las dos etapas de revision estan pendientes', () {
      expect(EstadoRuta.enRevision.pendienteDeRevision, isTrue);
      expect(EstadoRuta.revisionExperto.pendienteDeRevision, isTrue);
      expect(EstadoRuta.publicada.pendienteDeRevision, isFalse);
      expect(EstadoRuta.rechazada.pendienteDeRevision, isFalse);
    });
  });

  group('errorDelMotivo (criterio 6)', () {
    test('sin motivo no se puede rechazar', () {
      expect(errorDelMotivo(null), 'El motivo es obligatorio.');
      expect(errorDelMotivo(''), 'El motivo es obligatorio.');
    });

    test('un motivo de solo espacios tampoco cuenta', () {
      expect(errorDelMotivo('   \n '), 'El motivo es obligatorio.');
    });

    test('acepta el motivo justo en el limite y rechaza uno mas', () {
      expect(errorDelMotivo('a' * maxCaracteresMotivoRechazo), isNull);
      expect(
        errorDelMotivo('a' * (maxCaracteresMotivoRechazo + 1)),
        contains('300'),
      );
    });

    test('los espacios de los extremos no cuentan para el limite', () {
      expect(errorDelMotivo('  ${'a' * maxCaracteresMotivoRechazo}  '), isNull);
    });
  });
}
