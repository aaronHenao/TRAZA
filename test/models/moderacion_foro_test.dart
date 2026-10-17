import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';

import '../utiles/foro_repository_falso.dart';

/// La moderación del foro y los estados del contenido (SCRUM-322).
void main() {
  group('ModeracionForo', () {
    test('dice qué se moderó', () {
      expect(moderacionDePrueba().queEs, 'Publicación');
      expect(
        moderacionDePrueba(accion: AccionModeracion.edicion).queEs,
        'Edición de publicación',
      );
      expect(
        moderacionDePrueba(tipo: TipoModeracion.comentario).queEs,
        'Comentario',
      );
      expect(
        moderacionDePrueba(
          tipo: TipoModeracion.comentario,
          accion: AccionModeracion.edicion,
        ).queEs,
        'Edición de comentario',
      );
    });

    test('al autor no le dice qué administrador lo rechazó; al '
        'administrador sí', () {
      final porAdmin = moderacionDePrueba(
        responsable: ResponsableModeracion.admin,
        responsableNombre: 'David',
      );

      expect(porAdmin.responsableParaElAutor, 'Administrador');
      expect(porAdmin.responsableParaElAdmin, 'Administrador · David');
      expect(
        moderacionDePrueba().responsableParaElAdmin,
        'Moderación automática (IA)',
      );
    });

    test('lo que está en revisión o pendiente sigue abierto', () {
      expect(
        moderacionDePrueba(estado: EstadoModeracion.enRevision).abierta,
        isTrue,
      );
      expect(
        moderacionDePrueba(estado: EstadoModeracion.pendiente).abierta,
        isTrue,
      );
      expect(moderacionDePrueba().abierta, isFalse);
      expect(
        moderacionDePrueba(estado: EstadoModeracion.aprobada).abierta,
        isFalse,
      );
    });
  });

  test('las faltas de un autor son sus rechazos (SCRUM-338)', () {
    final moderaciones = [
      moderacionDePrueba(id: 'a', autorId: 'u1'),
      moderacionDePrueba(id: 'b', autorId: 'u1'),
      moderacionDePrueba(
        id: 'c',
        autorId: 'u1',
        estado: EstadoModeracion.aprobada,
      ),
      moderacionDePrueba(id: 'd', autorId: 'u2'),
    ];

    expect(faltasDe('u1', moderaciones), 2);
    expect(faltasDe('u2', moderaciones), 1);
    expect(faltasDe('u3', moderaciones), 0);
  });

  group('estados del contenido', () {
    test('lee cada estado de la base', () {
      expect(
        EstadoPublicacion.desdeDb('en_revision'),
        EstadoPublicacion.enRevision,
      );
      expect(
        EstadoPublicacion.desdeDb('pendiente'),
        EstadoPublicacion.pendiente,
      );
      expect(
        EstadoPublicacion.desdeDb('rechazada'),
        EstadoPublicacion.rechazada,
      );
      expect(EstadoPublicacion.desdeDb('retenida'), isNull);
    });

    test('al autor, en revisión y pendiente le esperan igual', () {
      expect(EstadoPublicacion.enRevision.esperaModeracion, isTrue);
      expect(EstadoPublicacion.pendiente.esperaModeracion, isTrue);
      expect(EstadoPublicacion.publicada.esperaModeracion, isFalse);
      expect(EstadoPublicacion.rechazada.esperaModeracion, isFalse);
    });

    test('un comentario en revisión no se edita, ni por su autor', () {
      final ComentarioForo enRevision = comentarioDePrueba(
        autorId: 'u1',
        estado: EstadoPublicacion.enRevision,
      );

      expect(enRevision.editablePor('u1'), isFalse);
      expect(comentarioDePrueba(autorId: 'u1').editablePor('u1'), isTrue);
    });
  });
}
