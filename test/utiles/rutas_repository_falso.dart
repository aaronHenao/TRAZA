import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';
import 'package:traza/services/rutas_service.dart';

/// Repositorio de rutas en memoria para las pruebas (SCRUM-241).
///
/// Guarda lo que recibe para poder comprobar qué se le mandó a la base, y
/// deja inyectar el error que debe lanzar al crear.
class RutasRepositorioFalso implements RutasRepository {
  RutasRepositorioFalso({this.existente, this.error, this.rutas = const []});

  /// La ruta que ya tiene el entrenamiento, para `rutaDeEntrenamiento`.
  final Ruta? existente;

  /// Lo que lanza `crear`, si algo.
  Object? error;

  final List<Ruta> rutas;

  /// Lo último que se mandó a crear, o null si no se llamó.
  NuevaRuta? recibida;

  int creaciones = 0;
  int consultasDeEntrenamiento = 0;

  /// Lo que devuelve `cercanas` (SCRUM-246). Sin esto, las publicadas en el
  /// orden en que están, a 1, 2, 3… km del usuario.
  List<RutaCercana>? rutasCercanas;

  /// Desde dónde y con qué radio se pidió la última consulta por cercanía.
  ({double latitud, double longitud, double radioKm})? ultimaConsultaCercana;

  int consultasCercanas = 0;
  int consultasPublicadas = 0;

  /// Lo que devuelve `buscar` (SCRUM-254). Sin esto, las publicadas cuyo
  /// nombre o creador contienen lo buscado, sin mirar mayúsculas.
  List<Ruta>? resultadosBusqueda;

  /// Lo que lanza `buscar`, si algo. Va aparte de [error] para que pueda
  /// fallar la búsqueda sin que falle la lista de siempre.
  Object? errorBusqueda;

  /// Cada búsqueda que llegó: qué se buscó y desde dónde.
  final busquedas = <({String termino, double? latitud, double? longitud})>[];

  @override
  Future<Ruta> crear(NuevaRuta ruta) async {
    recibida = ruta;
    creaciones++;

    final error = this.error;
    if (error != null) throw error;

    return rutaDePrueba(
      nombre: ruta.nombre,
      descripcion: ruta.descripcion,
      entrenamientoId: ruta.entrenamientoId,
      trazado: ruta.trazado,
    );
  }

  @override
  Future<List<Ruta>> misRutas() async => rutas;

  @override
  Future<List<Ruta>> publicadas() async {
    consultasPublicadas++;
    final error = this.error;
    if (error != null) throw error;
    return rutas.where((ruta) => ruta.publicada).toList();
  }

  @override
  Future<List<RutaCercana>> cercanas({
    required double latitud,
    required double longitud,
    required double radioKm,
  }) async {
    consultasCercanas++;
    ultimaConsultaCercana = (
      latitud: latitud,
      longitud: longitud,
      radioKm: radioKm,
    );

    final error = this.error;
    if (error != null) throw error;

    return rutasCercanas ??
        [
          for (final (i, ruta) in rutas.where((r) => r.publicada).indexed)
            RutaCercana(ruta: ruta, distanciaKm: i + 1.0),
        ];
  }

  @override
  Future<List<Ruta>> buscar({
    required String termino,
    double? latitud,
    double? longitud,
  }) async {
    busquedas.add((termino: termino, latitud: latitud, longitud: longitud));

    final error = errorBusqueda;
    if (error != null) throw error;

    final buscado = termino.toLowerCase();
    return resultadosBusqueda ??
        [
          for (final ruta in rutas)
            if (ruta.publicada &&
                '${ruta.nombre} ${ruta.autorNombre}'.toLowerCase().contains(
                  buscado,
                ))
              ruta,
        ];
  }

  @override
  Future<Ruta?> ruta(String id) async {
    final error = this.error;
    if (error != null) throw error;
    return rutas.where((ruta) => ruta.id == id).firstOrNull;
  }

  @override
  Future<Ruta?> rutaDeEntrenamiento(String entrenamientoId) async {
    consultasDeEntrenamiento++;
    return existente;
  }
}

/// Una ruta cualquiera, con lo mínimo que la pantalla necesita.
Ruta rutaDePrueba({
  String id = 'ruta-1',
  String nombre = 'Vuelta al estadio',
  String autorNombre = 'Ana',
  String? descripcion,
  String? entrenamientoId = 'e-123',
  EstadoRuta estado = EstadoRuta.enRevision,
  double? distanciaKm = 5.23,
  List<PuntoRuta> trazado = const [],
  List<PuntoRuta> miniatura = const [],
  DateTime? fechaPublicacion,
}) => Ruta(
  id: id,
  autorId: 'usuario-1',
  autorNombre: autorNombre,
  nombre: nombre,
  descripcion: descripcion,
  entrenamientoId: entrenamientoId,
  estado: estado,
  distanciaKm: distanciaKm,
  trazado: trazado,
  miniatura: miniatura,
  fechaCreacion: DateTime(2026, 10, 17, 9),
  fechaPublicacion: fechaPublicacion,
);
