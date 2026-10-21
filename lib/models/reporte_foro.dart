import 'package:flutter/foundation.dart';

/// Por qué un corredor reporta una publicación (SCRUM-369).
///
/// Las palabras salen de las normas de la comunidad
/// (`supabase/functions/moderar-foro/politica_traza.ts`), resumidas para
/// elegir rápido. Los valores coinciden con la restricción
/// `reportes_foro_motivo_valido` de `0036_foro_reportes.sql`: si cambia uno,
/// cambia en los dos lados.
enum MotivoReporte {
  odio('odio', 'Odio o discriminación'),
  acoso('acoso', 'Acoso o insultos'),
  contenidoSexual('contenido_sexual', 'Contenido sexual'),
  violencia('violencia', 'Violencia o amenazas'),
  spam('spam', 'Spam'),

  /// Pide contar por qué: sin eso no le dice nada al administrador.
  otro('otro', 'Otro');

  const MotivoReporte(this.valorDb, this.etiqueta);

  final String valorDb;
  final String etiqueta;

  static MotivoReporte? desdeDb(String? valor) =>
      values.where((m) => m.valorDb == valor).firstOrNull;
}

/// Lo que admite `reportes_foro_detalle_largo`.
const maxCaracteresDetalleReporte = 280;

/// Un reporte como lo ve el administrador en su bandeja (criterio 1 de
/// SCRUM-369).
///
/// A propósito no dice quién lo envió: la app nunca pide `reportante_id`
/// (criterio 2).
@immutable
class ReporteForo {
  const ReporteForo({
    required this.id,
    required this.publicacionId,
    required this.tituloPublicacion,
    required this.autorPublicacion,
    required this.motivo,
    required this.fecha,
    this.detalle,
  });

  final String id;
  final String publicacionId;
  final String tituloPublicacion;
  final String autorPublicacion;
  final MotivoReporte motivo;
  final String? detalle;
  final DateTime fecha;

  /// Una fila de `reportes_foro` con `publicaciones_foro(titulo,
  /// autor_nombre)` embebida.
  factory ReporteForo.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final publicacionId = fila['publicacion_id'];
    final motivo = MotivoReporte.desdeDb(fila['motivo'] as String?);
    final detalle = fila['detalle'];
    final fecha = fila['fecha'];
    final publicacion = fila['publicaciones_foro'];

    if (publicacion
        case {'titulo': final String titulo, 'autor_nombre': final String autor}
        when id is String &&
            publicacionId is String &&
            motivo != null &&
            (detalle == null || detalle is String) &&
            fecha is String) {
      return ReporteForo(
        id: id,
        publicacionId: publicacionId,
        tituloPublicacion: titulo,
        autorPublicacion: autor,
        motivo: motivo,
        detalle: detalle as String?,
        fecha: DateTime.parse(fecha).toLocal(),
      );
    }

    throw FormatException(
      'Fila de reportes_foro incompleta o inesperada',
      fila,
    );
  }

  @override
  bool operator ==(Object other) => other is ReporteForo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ReporteForo($publicacionId, ${motivo.valorDb})';
}

/// Una publicación de la bandeja del administrador con todos sus reportes
/// (criterio 1 de SCRUM-369): cuántas veces la reportaron y por qué.
@immutable
class PublicacionReportada {
  const PublicacionReportada({
    required this.publicacionId,
    required this.titulo,
    required this.autorNombre,
    required this.reportes,
  });

  final String publicacionId;
  final String titulo;
  final String autorNombre;
  final List<ReporteForo> reportes;

  int get cuantos => reportes.length;

  /// Los motivos sin repetir, el más reportado primero.
  List<MotivoReporte> get motivos {
    final veces = <MotivoReporte, int>{};
    for (final reporte in reportes) {
      veces.update(reporte.motivo, (n) => n + 1, ifAbsent: () => 1);
    }
    return veces.keys.toList()..sort((a, b) => veces[b]! - veces[a]!);
  }

  /// Lo que escribieron quienes la reportaron, sin los reportes que no
  /// traían detalle.
  List<String> get detalles => [
    for (final reporte in reportes)
      if (reporte.detalle case final detalle? when detalle.trim().isNotEmpty)
        detalle,
  ];

  DateTime get ultimoReporte => reportes
      .map((r) => r.fecha)
      .reduce((ultima, fecha) => fecha.isAfter(ultima) ? fecha : ultima);

  /// Junta [reportes] por publicación. La reportada más recientemente va
  /// primero: es la que el administrador debería mirar antes.
  static List<PublicacionReportada> agrupar(List<ReporteForo> reportes) {
    final porPublicacion = <String, List<ReporteForo>>{};
    for (final reporte in reportes) {
      porPublicacion.putIfAbsent(reporte.publicacionId, () => []).add(reporte);
    }

    return [
      for (final MapEntry(key: id, value: suyos) in porPublicacion.entries)
        PublicacionReportada(
          publicacionId: id,
          titulo: suyos.first.tituloPublicacion,
          autorNombre: suyos.first.autorPublicacion,
          reportes: List.unmodifiable(suyos),
        ),
    ]..sort((a, b) => b.ultimoReporte.compareTo(a.ultimoReporte));
  }
}
