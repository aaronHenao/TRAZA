import 'package:traza/models/notificacion.dart';
import 'package:traza/services/notificaciones_service.dart';

/// Repositorio de notificaciones en memoria para las pruebas.
///
/// Cuenta cuántas veces se marcaron como leídas, que es lo que distingue
/// "abrir la bandeja" de "mirar el contador".
class NotificacionesFalso implements NotificacionesRepository {
  NotificacionesFalso({
    this.notificaciones = const [],
    int? sinLeer,
    this.error,
  }) : _sinLeer =
           sinLeer ?? notificaciones.where((aviso) => !aviso.leida).length;

  final List<Notificacion> notificaciones;

  /// Lo que lanza `mias`, si algo.
  Object? error;

  int _sinLeer;
  int marcadas = 0;

  /// Cuantas veces se pidio la bandeja: los avisos llegan cuando el usuario
  /// no esta mirando, asi que volver a entrar tiene que volver a preguntar.
  int consultas = 0;

  @override
  Future<List<Notificacion>> mias() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return notificaciones;
  }

  @override
  Future<int> sinLeer() async => _sinLeer;

  @override
  Future<void> marcarTodasLeidas() async {
    marcadas++;
    _sinLeer = 0;
  }
}

/// Un aviso cualquiera, con lo mínimo que la bandeja necesita.
Notificacion notificacionDePrueba({
  String id = 'aviso-1',
  TipoNotificacion tipo = TipoNotificacion.rutaPublicada,
  String titulo = 'Tu ruta ya está publicada',
  String mensaje = '"Vuelta al estadio" ya la puede ver la comunidad.',
  String? entidadId = 'ruta-1',
  DateTime? leidaEn,
  DateTime? fechaCreacion,
}) => Notificacion(
  id: id,
  tipo: tipo,
  titulo: titulo,
  mensaje: mensaje,
  entidadId: entidadId,
  leidaEn: leidaEn,
  fechaCreacion: fechaCreacion ?? DateTime(2026, 10, 17, 9),
);
