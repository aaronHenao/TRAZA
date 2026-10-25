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
///
/// Desde SCRUM-363 hace de base compartida: lo que se crea queda en [rutas],
/// y clasificar y confirmar cambian la ruta guardada con las mismas reglas
/// que `clasificar_ruta` y `confirmar_publicacion_ruta` (0045). Así una
/// prueba puede pasar del autor al experto y de vuelta al autor con el mismo
/// doble, cambiando [usuario].
class RutasRepositorioFalso implements RutasRepository {
  RutasRepositorioFalso({
    this.existente,
    this.error,
    List<Ruta> rutas = const [],
    this.usuario = 'usuario-1',
  }) : rutas = [...rutas];

  /// La ruta que ya tiene el entrenamiento, para `rutaDeEntrenamiento`.
  final Ruta? existente;

  /// Lo que lanza `crear`, si algo.
  Object? error;

  /// Lo que hay en la tabla. Crear, clasificar y confirmar la cambian.
  final List<Ruta> rutas;

  /// Quién tiene la sesión abierta, o null si nadie (SCRUM-363). Es a nombre
  /// de quién se crea, y lo que la base mira para decidir si puede
  /// clasificar o confirmar.
  String? usuario;

  /// La distancia que la base le calcula a la próxima ruta que se cree, o
  /// null si su entrenamiento no la registró. Sin distancia nace con la
  /// dificultad pendiente, como en `preparar_ruta` (criterio 3 de SCRUM-363).
  double? distanciaNueva = 5.23;

  /// Lo que lanza `porClasificar`, si algo. Aparte de [error] para que la
  /// bandeja pueda fallar sin que falle el detalle.
  Object? errorPorClasificar;

  /// Lo que lanza `clasificar` antes de mirar la ruta, si algo.
  Object? errorClasificacion;

  /// Lo que lanza `confirmarPublicacion` antes de mirar la ruta, si algo.
  Object? errorConfirmacion;

  int consultasPorClasificar = 0;

  /// Cuántas veces se pidió el detalle de una ruta (SCRUM-363).
  int consultasDeRuta = 0;

  /// Cada clasificación que llegó, aunque la base la rechazara.
  final clasificaciones = <({String rutaId, Dificultad dificultad})>[];

  /// El id de cada ruta cuya publicación se pidió confirmar.
  final confirmaciones = <String>[];

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

    // Como `preparar_ruta` (0045): el estado lo decide la base según tenga
    // o no distancia, y la dificultad nace vacía.
    final distancia = distanciaNueva;
    final creada = rutaDePrueba(
      id: 'ruta-nueva',
      autorId: usuario ?? 'usuario-1',
      nombre: ruta.nombre,
      descripcion: ruta.descripcion,
      entrenamientoId: ruta.entrenamientoId,
      trazado: ruta.trazado,
      distanciaKm: distancia,
      estado: distancia == null
          ? EstadoRuta.datosIncompletos
          : EstadoRuta.enRevision,
    );
    rutas.add(creada);
    return creada;
  }

  @override
  Future<List<Ruta>> porClasificar() async {
    consultasPorClasificar++;
    final error = errorPorClasificar;
    if (error != null) throw error;

    // La consulta de la app: las ajenas que están en revisión, la más
    // antigua primero. Las que no tienen distancia no llegan (criterio 3).
    return rutas
        .where(
          (ruta) =>
              ruta.estado == EstadoRuta.enRevision && ruta.autorId != usuario,
        )
        .toList()
      ..sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));
  }

  @override
  Future<Ruta> clasificar(Ruta ruta, Dificultad dificultad) async {
    clasificaciones.add((rutaId: ruta.id, dificultad: dificultad));

    final error = errorClasificacion;
    if (error != null) throw error;

    final usuario = this.usuario;
    if (usuario == null) throw const SesionRequeridaParaRutasException();

    // En el orden de `clasificar_ruta`: primero si sigue en revisión, luego
    // si es suya.
    final i = rutas.indexWhere((guardada) => guardada.id == ruta.id);
    if (i < 0 || rutas[i].estado != EstadoRuta.enRevision) {
      throw const RutaCambioDeEstadoException();
    }
    if (rutas[i].autorId == usuario) {
      throw const SinPermisoSobreRutaException();
    }

    return rutas[i] = _cambiada(
      rutas[i],
      estado: EstadoRuta.clasificada,
      dificultad: dificultad,
    );
  }

  @override
  Future<Ruta> confirmarPublicacion(Ruta ruta) async {
    confirmaciones.add(ruta.id);

    final error = errorConfirmacion;
    if (error != null) throw error;

    final usuario = this.usuario;
    if (usuario == null) throw const SesionRequeridaParaRutasException();

    // En el orden de `confirmar_publicacion_ruta`: que exista, que sea suya
    // y que esté esperando su confirmación.
    final i = rutas.indexWhere((guardada) => guardada.id == ruta.id);
    if (i < 0) throw const RutaCambioDeEstadoException();
    if (rutas[i].autorId != usuario) {
      throw const SinPermisoSobreRutaException();
    }
    if (rutas[i].estado != EstadoRuta.clasificada) {
      throw const RutaCambioDeEstadoException();
    }

    return rutas[i] = _cambiada(
      rutas[i],
      estado: EstadoRuta.publicada,
      dificultad: rutas[i].dificultad,
      fechaPublicacion: DateTime(2026, 10, 17, 12),
    );
  }

  /// [ruta] con otro estado y otra dificultad; lo demás, igual.
  static Ruta _cambiada(
    Ruta ruta, {
    required EstadoRuta estado,
    required Dificultad? dificultad,
    DateTime? fechaPublicacion,
  }) => Ruta(
    id: ruta.id,
    autorId: ruta.autorId,
    autorNombre: ruta.autorNombre,
    nombre: ruta.nombre,
    estado: estado,
    fechaCreacion: ruta.fechaCreacion,
    entrenamientoId: ruta.entrenamientoId,
    descripcion: ruta.descripcion,
    trazado: ruta.trazado,
    miniatura: ruta.miniatura,
    distanciaKm: ruta.distanciaKm,
    dificultad: dificultad,
    motivoRechazo: ruta.motivoRechazo,
    fechaPublicacion: fechaPublicacion ?? ruta.fechaPublicacion,
  );

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
    // La indicada, como está ahora en la lista (si se clasificó o publicó
    // después, con su estado nuevo). Sin una indicada, la que el usuario ya
    // creó de ese entrenamiento, como la consulta de la app: las rechazadas
    // no cuentan.
    final indicada = existente;
    if (indicada != null) {
      return rutas.where((ruta) => ruta.id == indicada.id).firstOrNull ??
          indicada;
    }
    return rutas
        .where(
          (ruta) =>
              ruta.autorId == usuario &&
              ruta.entrenamientoId == entrenamientoId &&
              ruta.estado != EstadoRuta.rechazada,
        )
        .firstOrNull;
  }
}

/// Una ruta cualquiera, con lo mínimo que la pantalla necesita.
Ruta rutaDePrueba({
  String id = 'ruta-1',
  String autorId = 'usuario-1',
  String nombre = 'Vuelta al estadio',
  String autorNombre = 'Ana',
  String? descripcion,
  String? entrenamientoId = 'e-123',
  EstadoRuta estado = EstadoRuta.enRevision,
  double? distanciaKm = 5.23,
  Dificultad? dificultad,
  List<PuntoRuta> trazado = const [],
  List<PuntoRuta> miniatura = const [],
  DateTime? fechaCreacion,
  DateTime? fechaPublicacion,
}) => Ruta(
  id: id,
  autorId: autorId,
  autorNombre: autorNombre,
  nombre: nombre,
  descripcion: descripcion,
  entrenamientoId: entrenamientoId,
  estado: estado,
  distanciaKm: distanciaKm,
  dificultad: dificultad,
  trazado: trazado,
  miniatura: miniatura,
  fechaCreacion: fechaCreacion ?? DateTime(2026, 10, 17, 9),
  fechaPublicacion: fechaPublicacion,
);
