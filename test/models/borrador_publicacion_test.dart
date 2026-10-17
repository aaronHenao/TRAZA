import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/publicacion_foro.dart';

/// Validación de una publicación antes de enviarla (SCRUM-345) y lectura de
/// las filas de `publicaciones_foro`.
void main() {
  group('BorradorPublicacion', () {
    test('con título y contenido es válido y se envía sin espacios de más', () {
      const borrador = BorradorPublicacion(
        titulo: '  Primera media maratón  ',
        contenido: '\n¿Cuántas semanas de preparación?  ',
      );

      expect(borrador.errores, isEmpty);
      final nueva = borrador.aNuevaPublicacion()!;
      expect(nueva.titulo, 'Primera media maratón');
      expect(nueva.contenido, '¿Cuántas semanas de preparación?');
    });

    test('sin título ni contenido señala los dos campos', () {
      const borrador = BorradorPublicacion();

      expect(borrador.errores, {
        CampoPublicacion.titulo: 'Ponle un título a tu publicación.',
        CampoPublicacion.contenido: 'Escribe el contenido de tu publicación.',
      });
      expect(borrador.aNuevaPublicacion(), isNull);
    });

    test('solo espacios no cuenta como contenido', () {
      const borrador = BorradorPublicacion(titulo: '   ', contenido: ' \n ');

      expect(
        borrador.errores.keys,
        containsAll([CampoPublicacion.titulo, CampoPublicacion.contenido]),
      );
    });

    test('acepta el título justo en el límite y rechaza un carácter más', () {
      final enElLimite = BorradorPublicacion(
        titulo: 'a' * maxCaracteresTituloPublicacion,
        contenido: 'Contenido',
      );
      final pasado = BorradorPublicacion(
        titulo: 'a' * (maxCaracteresTituloPublicacion + 1),
        contenido: 'Contenido',
      );

      expect(enElLimite.esValido, isTrue);
      expect(
        pasado.errores[CampoPublicacion.titulo],
        'El título no puede superar 120 caracteres.',
      );
    });

    test('acepta el contenido justo en el límite y rechaza uno más', () {
      final enElLimite = BorradorPublicacion(
        titulo: 'Título',
        contenido: 'a' * maxCaracteresContenidoPublicacion,
      );
      final pasado = BorradorPublicacion(
        titulo: 'Título',
        contenido: 'a' * (maxCaracteresContenidoPublicacion + 1),
      );

      expect(enElLimite.esValido, isTrue);
      expect(
        pasado.errores[CampoPublicacion.contenido],
        'El contenido no puede superar 2000 caracteres.',
      );
      expect(pasado.aNuevaPublicacion(), isNull);
    });

    test('lo que se envía no lleva autor ni estado: los pone la base', () {
      final nueva = const BorradorPublicacion(
        titulo: 'Título',
        contenido: 'Contenido',
      ).aNuevaPublicacion()!;

      expect(nueva.aSupabase(), {'titulo': 'Título', 'contenido': 'Contenido'});
    });
  });

  group('PublicacionForo.desdeSupabase', () {
    test('lee una fila completa', () {
      final publicacion = PublicacionForo.desdeSupabase({
        'id': 'pub-1',
        'autor_id': 'u-1',
        'autor_nombre': 'Ana',
        'titulo': 'Hola',
        'contenido': 'Primera vez aquí',
        'estado': 'retenida',
        'motivo_moderacion': 'spam',
        'fecha_creacion': '2026-10-16T14:00:00+00:00',
      });

      expect(publicacion.autorNombre, 'Ana');
      expect(publicacion.estado, EstadoPublicacion.retenida);
      expect(publicacion.motivoModeracion, 'spam');
      expect(publicacion.fechaCreacion.toUtc(), DateTime.utc(2026, 10, 16, 14));
    });

    test('rechaza una fila con un estado desconocido', () {
      expect(
        () => PublicacionForo.desdeSupabase({
          'id': 'pub-1',
          'autor_id': 'u-1',
          'autor_nombre': 'Ana',
          'titulo': 'Hola',
          'contenido': 'Texto',
          'estado': 'borrador',
          'fecha_creacion': '2026-10-16T14:00:00+00:00',
        }),
        throwsFormatException,
      );
    });
  });
}
