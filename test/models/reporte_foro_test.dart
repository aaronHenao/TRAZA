import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/reporte_foro.dart';

import '../utiles/foro_repository_falso.dart';

/// Los reportes de publicaciones del foro (SCRUM-369): los motivos, cómo los
/// lee el administrador, cómo se agrupan en su bandeja y a quién se le
/// ofrece reportar.
void main() {
  group('MotivoReporte', () {
    test('sus valores son los del check reportes_foro_motivo_valido', () {
      expect(MotivoReporte.values.map((m) => m.valorDb), [
        'odio',
        'acoso',
        'contenido_sexual',
        'violencia',
        'spam',
        'otro',
      ]);
    });

    test('se le muestran al corredor con las palabras de las normas', () {
      expect(MotivoReporte.values.map((m) => m.etiqueta), [
        'Odio o discriminación',
        'Acoso o insultos',
        'Contenido sexual',
        'Violencia o amenazas',
        'Spam',
        'Otro',
      ]);
    });

    test('cada motivo se lee de la base y lo desconocido no', () {
      for (final motivo in MotivoReporte.values) {
        expect(MotivoReporte.desdeDb(motivo.valorDb), motivo);
      }
      expect(MotivoReporte.desdeDb('grosero'), isNull);
      expect(MotivoReporte.desdeDb(null), isNull);
    });

    test('el detalle admite lo mismo que el check de la base', () {
      expect(maxCaracteresDetalleReporte, 280);
    });
  });

  group('ReporteForo.desdeSupabase', () {
    final fila = <String, dynamic>{
      'id': 'rep-1',
      'publicacion_id': 'pub-1',
      'motivo': 'contenido_sexual',
      'detalle': 'Fotos fuera de lugar',
      'fecha': '2026-10-16T14:00:00+00:00',
      'publicaciones_foro': {'titulo': 'Tenis', 'autor_nombre': 'Carlos'},
    };

    test('lee el reporte con el título y el autor de la publicación '
        'embebida (criterio 1 de SCRUM-369)', () {
      final reporte = ReporteForo.desdeSupabase(fila);

      expect(reporte.id, 'rep-1');
      expect(reporte.publicacionId, 'pub-1');
      expect(reporte.tituloPublicacion, 'Tenis');
      expect(reporte.autorPublicacion, 'Carlos');
      expect(reporte.motivo, MotivoReporte.contenidoSexual);
      expect(reporte.detalle, 'Fotos fuera de lugar');
      expect(reporte.fecha.toUtc(), DateTime.utc(2026, 10, 16, 14));
    });

    test('el detalle es opcional', () {
      final reporte = ReporteForo.desdeSupabase({...fila, 'detalle': null});

      expect(reporte.detalle, isNull);
    });

    test('una fila con un motivo desconocido no se acepta', () {
      expect(
        () => ReporteForo.desdeSupabase({...fila, 'motivo': 'grosero'}),
        throwsFormatException,
      );
    });
  });

  group('PublicacionReportada.agrupar (bandeja del administrador)', () {
    // A 'a' la reportaron tres veces; a 'b', una, después que a 'a'.
    final reportes = [
      reporteDePrueba(
        id: 'r1',
        publicacionId: 'a',
        tituloPublicacion: 'Tenis para asfalto',
        autorPublicacion: 'Carlos',
        motivo: MotivoReporte.spam,
        fecha: DateTime(2026, 10, 16, 9),
      ),
      reporteDePrueba(
        id: 'r2',
        publicacionId: 'a',
        tituloPublicacion: 'Tenis para asfalto',
        autorPublicacion: 'Carlos',
        motivo: MotivoReporte.acoso,
        fecha: DateTime(2026, 10, 16, 11),
      ),
      reporteDePrueba(
        id: 'r3',
        publicacionId: 'b',
        tituloPublicacion: 'Gana dinero fácil',
        autorPublicacion: 'Spammer',
        motivo: MotivoReporte.odio,
        fecha: DateTime(2026, 10, 16, 12),
      ),
      reporteDePrueba(
        id: 'r4',
        publicacionId: 'a',
        tituloPublicacion: 'Tenis para asfalto',
        autorPublicacion: 'Carlos',
        motivo: MotivoReporte.acoso,
        fecha: DateTime(2026, 10, 16, 8),
      ),
    ];

    PublicacionReportada de(List<PublicacionReportada> bandeja, String id) =>
        bandeja.singleWhere((p) => p.publicacionId == id);

    test('sin reportes la bandeja queda vacía', () {
      expect(PublicacionReportada.agrupar(const []), isEmpty);
    });

    test('junta los reportes de cada publicación y cuenta cuántos tiene '
        '(criterio 1 de SCRUM-369)', () {
      final bandeja = PublicacionReportada.agrupar(reportes);

      expect(bandeja, hasLength(2));
      final a = de(bandeja, 'a');
      expect(a.titulo, 'Tenis para asfalto');
      expect(a.autorNombre, 'Carlos');
      expect(a.cuantos, 3);
      expect(a.reportes.map((r) => r.id), unorderedEquals(['r1', 'r2', 'r4']));
      expect(a.ultimoReporte, DateTime(2026, 10, 16, 11));
      expect(de(bandeja, 'b').cuantos, 1);
    });

    test('los motivos van sin repetir y el más reportado primero', () {
      final bandeja = PublicacionReportada.agrupar(reportes);

      expect(de(bandeja, 'a').motivos, [
        MotivoReporte.acoso,
        MotivoReporte.spam,
      ]);
      expect(de(bandeja, 'b').motivos, [MotivoReporte.odio]);
    });

    test('junta lo que contó cada corredor y salta los reportes sin '
        'detalle (criterio 1 de SCRUM-369)', () {
      final bandeja = PublicacionReportada.agrupar([
        reporteDePrueba(id: 'r1', motivo: MotivoReporte.otro, detalle: 'Doxeo'),
        reporteDePrueba(id: 'r2'),
        reporteDePrueba(id: 'r3', detalle: '   '),
      ]);

      expect(bandeja.single.detalles, ['Doxeo']);
    });

    test('la publicación reportada más recientemente va primero, aunque sus '
        'reportes lleguen después en la lista', () {
      final bandeja = PublicacionReportada.agrupar(reportes);

      expect(bandeja.map((p) => p.publicacionId), ['b', 'a']);
    });
  });

  group('PublicacionForo.reportablePor', () {
    // `publicacionDePrueba(id: 'pub-1')` la escribió 'autor-pub-1'.

    test('se ofrece reportar lo publicado de otro (criterio 1 de '
        'SCRUM-369)', () {
      expect(publicacionDePrueba().reportablePor('usuario-1'), isTrue);
    });

    test('lo propio no se reporta', () {
      expect(publicacionDePrueba().reportablePor('autor-pub-1'), isFalse);
    });

    test('lo que espera la moderación o ya salió del foro no se reporta', () {
      for (final estado in [
        EstadoPublicacion.enRevision,
        EstadoPublicacion.pendiente,
        EstadoPublicacion.rechazada,
        EstadoPublicacion.eliminada,
      ]) {
        expect(
          publicacionDePrueba(estado: estado).reportablePor('usuario-1'),
          isFalse,
          reason: estado.valorDb,
        );
      }
    });

    test('sin sesión no se ofrece', () {
      expect(publicacionDePrueba().reportablePor(null), isFalse);
    });
  });
}
