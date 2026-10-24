import 'dart:async';

import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';
import 'package:traza/models/zona.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/utils/texto_para_buscar.dart';

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
  /// nombre o creador coinciden con lo buscado, como lo compara la base.
  List<Ruta>? resultadosBusqueda;

  /// Lo que lanza `buscar`, si algo. Va aparte de [error] para que pueda
  /// fallar la búsqueda sin que falle la lista de siempre.
  Object? errorBusqueda;

  /// Lo que `buscar` agrega cuando llega una zona (SCRUM-255): las rutas que
  /// arrancan en ella. El falso no sabe dónde arranca cada ruta, así que la
  /// prueba se las dice.
  List<Ruta> rutasEnZona = const [];

  /// Cada búsqueda que llegó: qué se buscó, desde dónde y en qué zona.
  final busquedas =
      <({String termino, double? latitud, double? longitud, Zona? zona})>[];

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
    Zona? zona,
  }) async {
    busquedas.add((
      termino: termino,
      latitud: latitud,
      longitud: longitud,
      zona: zona,
    ));

    final error = errorBusqueda;
    if (error != null) throw error;

    // Como compara la base (0041): cada palabra escrita tiene que ser el
    // comienzo de una palabra del nombre o del creador.
    final palabras = textoParaBuscar(termino).split(' ');
    bool coincide(Ruta ruta) {
      final texto = ' ${textoParaBuscar('${ruta.nombre} ${ruta.autorNombre}')}';
      return palabras.every((palabra) => texto.contains(' $palabra'));
    }

    final porTexto =
        resultadosBusqueda ??
        [
          for (final ruta in rutas)
            if (ruta.publicada && coincide(ruta)) ruta,
        ];
    return [
      ...porTexto,
      if (zona != null)
        for (final ruta in rutasEnZona)
          if (!porTexto.contains(ruta)) ruta,
    ];
  }

  /// Lo que contesta `puedeRevisarClasificacion` (SCRUM-261). Por defecto,
  /// que no: así es para casi todos los usuarios.
  bool puedeRevisar = false;

  /// Lo que lanza `puedeRevisarClasificacion`, si algo.
  Object? errorPermisoRevision;

  /// Las rutas por las que se preguntó si se podían revisar.
  final permisosDeRevision = <String>[];

  @override
  Future<bool> puedeRevisarClasificacion(String rutaId) async {
    permisosDeRevision.add(rutaId);
    final error = errorPermisoRevision;
    if (error != null) throw error;
    return puedeRevisar;
  }

  /// Las rutas cuya clasificación se confirmó (SCRUM-262).
  final confirmadas = <String>[];

  /// Lo que lanza `confirmarClasificacion`, si algo.
  Object? errorConfirmar;

  /// Si está, `confirmarClasificacion` no termina hasta que la prueba lo
  /// complete.
  Completer<void>? confirmacionPendiente;

  @override
  Future<void> confirmarClasificacion(String rutaId) async {
    confirmadas.add(rutaId);
    final error = errorConfirmar;
    if (error != null) throw error;
    await confirmacionPendiente?.future;
  }

  /// Las correcciones de la clasificación que llegaron, en orden (SCRUM-263).
  final corregidas = <(String, Dificultad)>[];

  /// Lo que lanza `corregirClasificacion`, si algo.
  Object? errorCorregir;

  /// Si está, `corregirClasificacion` no termina hasta que la prueba lo
  /// complete.
  Completer<void>? correccionPendiente;

  @override
  Future<void> corregirClasificacion(
    String rutaId,
    Dificultad dificultad,
  ) async {
    corregidas.add((rutaId, dificultad));
    final error = errorCorregir;
    if (error != null) throw error;
    await correccionPendiente?.future;
  }

  /// Cuántas veces se pidió una ruta con su trazado.
  int consultasDeRuta = 0;

  @override
  Future<Ruta?> ruta(String id) async {
    consultasDeRuta++;
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
  Dificultad? dificultad,
  DateTime? dificultadRevisadaEn,
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
  dificultad: dificultad,
  dificultadRevisadaEn: dificultadRevisadaEn,
  trazado: trazado,
  miniatura: miniatura,
  fechaCreacion: DateTime(2026, 10, 17, 9),
  fechaPublicacion: fechaPublicacion,
);
