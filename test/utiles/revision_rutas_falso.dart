import 'package:traza/models/ruta.dart';
import 'package:traza/services/revision_rutas_service.dart';

/// Revisión de rutas en memoria para las pruebas (SCRUM-321).
///
/// Mueve las rutas de etapa como lo hace `decidir_revision_ruta` desde
/// `0048`: aprobar en la del administrador la manda al experto, el experto
/// no aprueba por aquí (eso es `clasificar_ruta`), y rechazar en cualquiera
/// la deja rechazada con su motivo. Guarda cada decisión para comprobar qué
/// se mandó.
class RevisionRutasFalso implements RevisionRutasRepository {
  RevisionRutasFalso({List<Ruta> rutas = const [], this.error})
    : rutas = [...rutas];

  /// Todas las rutas, en cualquier estado.
  final List<Ruta> rutas;

  /// Lo que lanzan `pendientes` y `decidir`, si algo.
  Object? error;

  /// Lo que lanza solo `decidir`, si algo.
  Object? errorAlDecidir;

  /// Cada decisión recibida: (ruta, aprobar, motivo).
  final decisiones = <(String, bool, String?)>[];

  int consultas = 0;

  @override
  Future<List<Ruta>> pendientes() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return rutas.where((r) => r.estado == EstadoRuta.enRevision).toList();
  }

  @override
  Future<Ruta> decidir(
    String rutaId, {
    required bool aprobar,
    String? motivo,
  }) async {
    decisiones.add((rutaId, aprobar, motivo));
    final error = errorAlDecidir ?? this.error;
    if (error != null) throw error;

    final indice = rutas.indexWhere((r) => r.id == rutaId);
    if (indice < 0) throw const RutaYaRevisadaException();
    final ruta = rutas[indice];

    final siguiente = switch (ruta.estado) {
      EstadoRuta.enRevision when aprobar => EstadoRuta.revisionExperto,
      EstadoRuta.revisionExperto when aprobar =>
        throw const RevisionNoPermitidaException(),
      EstadoRuta.enRevision ||
      EstadoRuta.revisionExperto => EstadoRuta.rechazada,
      _ => throw const RutaYaRevisadaException(),
    };

    final revisada = conEstado(
      ruta,
      siguiente,
      motivoRechazo: aprobar ? null : motivo,
    );
    rutas[indice] = revisada;
    return revisada;
  }
}

/// [ruta] con otro estado: `Ruta` no tiene `copyWith`.
Ruta conEstado(Ruta ruta, EstadoRuta estado, {String? motivoRechazo}) => Ruta(
  id: ruta.id,
  autorId: ruta.autorId,
  autorNombre: ruta.autorNombre,
  nombre: ruta.nombre,
  estado: estado,
  fechaCreacion: ruta.fechaCreacion,
  entrenamientoId: ruta.entrenamientoId,
  descripcion: ruta.descripcion,
  trazado: ruta.trazado,
  distanciaKm: ruta.distanciaKm,
  motivoRechazo: motivoRechazo,
  fechaPublicacion: estado == EstadoRuta.publicada
      ? DateTime(2026, 10, 18, 12)
      : ruta.fechaPublicacion,
);
