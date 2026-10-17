import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/services/foro_service.dart';

/// Doble de `ForoRepository` con el foro en memoria.
///
/// Anota lo que recibe, lanza [error] si se le indica y crea las
/// publicaciones con el [estadoAlCrear] que la prueba quiera simular que puso
/// la base.
class ForoRepositorioFalso implements ForoRepository {
  ForoRepositorioFalso({
    List<PublicacionForo>? publicaciones,
    this.estadoAlCrear = EstadoPublicacion.publicada,
    this.ahora,
  }) : publicaciones = [...?publicaciones];

  final List<PublicacionForo> publicaciones;
  EstadoPublicacion estadoAlCrear;
  DateTime? ahora;

  Object? error;
  NuevaPublicacion? recibida;
  int consultas = 0;

  @override
  Future<PublicacionForo> crear(NuevaPublicacion publicacion) async {
    recibida = publicacion;
    final error = this.error;
    if (error != null) throw error;

    final creada = PublicacionForo(
      id: 'pub-${publicaciones.length + 1}',
      autorId: 'usuario-1',
      autorNombre: 'Ana Runner',
      titulo: publicacion.titulo,
      contenido: publicacion.contenido,
      estado: estadoAlCrear,
      fechaCreacion: ahora ?? DateTime(2026, 10, 16, 9),
    );
    publicaciones.insert(0, creada);
    return creada;
  }

  @override
  Future<List<PublicacionForo>> publicadas() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return publicaciones
        .where((p) => p.estado == EstadoPublicacion.publicada)
        .toList();
  }

  @override
  Future<List<PublicacionForo>> todasParaModeracion() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return [...publicaciones];
  }
}

/// Una publicación de ejemplo para las pruebas.
PublicacionForo publicacionDePrueba({
  String id = 'pub-1',
  String titulo = '¿Qué tenis para asfalto?',
  String contenido = 'Busco recomendaciones para correr 10 km.',
  String autorNombre = 'Carlos',
  EstadoPublicacion estado = EstadoPublicacion.publicada,
  DateTime? fecha,
  String? motivo,
}) => PublicacionForo(
  id: id,
  autorId: 'autor-$id',
  autorNombre: autorNombre,
  titulo: titulo,
  contenido: contenido,
  estado: estado,
  fechaCreacion: fecha ?? DateTime(2026, 10, 16, 8),
  motivoModeracion: motivo,
);
