import 'package:flutter/foundation.dart';

import 'punto_gps.dart';

/// En qué situación está una ruta de la comunidad.
///
/// Los nombres coinciden con la restricción `estado in (...)` de la tabla
/// `rutas` (`0029_rutas.sql`).
enum EstadoRuta {
  /// Esperando a que un Runner Experto la apruebe (criterio 1 de SCRUM-241).
  /// Solo la ven su autor, el experto y el administrador.
  enRevision('en_revision'),

  /// Aprobada y visible para toda la comunidad.
  publicada('publicada'),

  /// El experto no la aprobó. La ve su autor con el motivo.
  rechazada('rechazada');

  const EstadoRuta(this.valorDb);

  final String valorDb;

  static EstadoRuta? desdeDb(String? valor) {
    for (final estado in values) {
      if (estado.valorDb == valor) return estado;
    }
    return null;
  }
}

/// Un punto del trazado de una ruta: dónde, y nada más.
///
/// No es un [PuntoGps]: ese trae el instante de la lectura, su precisión y
/// su velocidad, que describen *una carrera*. Una ruta es un camino que otro
/// va a seguir, y de él solo importa por dónde pasa.
@immutable
class PuntoRuta {
  const PuntoRuta({required this.latitud, required this.longitud});

  final double latitud;
  final double longitud;

  /// Como se guarda en `rutas.trazado`.
  Map<String, double> aJson() => {'lat': latitud, 'lng': longitud};

  static PuntoRuta? desdeJson(Object? json) {
    if (json case {'lat': final num lat, 'lng': final num lng}) {
      return PuntoRuta(latitud: lat.toDouble(), longitud: lng.toDouble());
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PuntoRuta &&
      other.latitud == latitud &&
      other.longitud == longitud;

  @override
  int get hashCode => Object.hash(latitud, longitud);

  @override
  String toString() => 'PuntoRuta($latitud, $longitud)';
}

/// Cuántos puntos conserva el trazado de una ruta como máximo.
///
/// El recorrido se graba con un punto cada 5 m
/// (`ConfiguracionRastreo.distanciaMinimaRegistroMetros`), así que una hora
/// de carrera deja miles. Guardarlos todos no mejora el camino que se sigue
/// y sí pesa en cada consulta y en cada dibujado, y el trazado se escribe
/// una sola vez: lo que entre mal se queda mal.
///
/// Con 500 puntos, una ruta de 10 km conserva uno cada 20 m.
const maxPuntosTrazadoRuta = 500;

/// Una ruta de la comunidad, tal como vive en `rutas` (SCRUM-241).
///
/// El nombre del autor, el estado, el punto de inicio, la distancia y las
/// fechas los pone la base al insertarla, no el cliente.
@immutable
class Ruta {
  const Ruta({
    required this.id,
    required this.autorId,
    required this.autorNombre,
    required this.nombre,
    required this.estado,
    required this.fechaCreacion,
    this.entrenamientoId,
    this.descripcion,
    this.trazado = const [],
    this.distanciaKm,
    this.motivoRechazo,
    this.fechaPublicacion,
  });

  final String id;
  final String autorId;

  /// Quién la publicó, para mostrarlo a los demás (criterio 4).
  final String autorNombre;

  final String nombre;
  final EstadoRuta estado;
  final DateTime fechaCreacion;

  /// De qué entrenamiento salió. Queda en null si su autor lo borró: la ruta
  /// sobrevive porque la comunidad ya la usa.
  final String? entrenamientoId;

  final String? descripcion;

  /// Por dónde pasa, en orden. Vacío en las consultas que no lo piden: un
  /// listado no necesita el trazado de cada ruta para pintarse.
  final List<PuntoRuta> trazado;

  /// Cuántos km mide, o null si no está registrada (criterio 4 de
  /// SCRUM-240). La calcula la base al guardar la ruta.
  final double? distanciaKm;

  /// Por qué el experto no la aprobó. Null mientras no la rechace.
  final String? motivoRechazo;

  /// Cuándo quedó publicada, para mostrarlo junto al autor (criterio 4).
  /// Null hasta que se apruebe.
  final DateTime? fechaPublicacion;

  bool get publicada => estado == EstadoRuta.publicada;

  /// Si se le puede mostrar la distancia a alguien (criterio 4 de
  /// SCRUM-240: cuando no, hay que avisar).
  bool get tieneDistancia => distanciaKm != null;

  factory Ruta.desdeSupabase(Map<String, dynamic> fila) {
    final id = fila['id'];
    final autorId = fila['autor_id'];
    final autorNombre = fila['autor_nombre'];
    final nombre = fila['nombre'];
    final estado = EstadoRuta.desdeDb(fila['estado'] as String?);
    final creacion = fila['fecha_creacion'];
    final publicacion = fila['fecha_publicacion'];
    final descripcion = fila['descripcion'];
    final motivo = fila['motivo_rechazo'];
    final entrenamiento = fila['entrenamiento_id'];

    if (id is! String ||
        autorId is! String ||
        autorNombre is! String ||
        nombre is! String ||
        estado == null ||
        creacion is! String ||
        (publicacion != null && publicacion is! String) ||
        (descripcion != null && descripcion is! String) ||
        (motivo != null && motivo is! String) ||
        (entrenamiento != null && entrenamiento is! String)) {
      throw FormatException('Fila de rutas incompleta o inesperada', fila);
    }

    return Ruta(
      id: id,
      autorId: autorId,
      autorNombre: autorNombre,
      nombre: nombre,
      estado: estado,
      fechaCreacion: DateTime.parse(creacion).toLocal(),
      entrenamientoId: entrenamiento as String?,
      descripcion: descripcion as String?,
      trazado: trazadoDesdeJson(fila['trazado']),
      distanciaKm: _comoDouble(fila['distancia_km']),
      motivoRechazo: motivo as String?,
      fechaPublicacion: publicacion is String
          ? DateTime.parse(publicacion).toLocal()
          : null,
    );
  }

  /// Lee `rutas.trazado`. Los puntos que no traigan coordenadas se descartan
  /// en vez de reventar la lectura: el trigger de la base no los deja
  /// entrar, así que uno así solo puede venir de una fila escrita a mano.
  static List<PuntoRuta> trazadoDesdeJson(Object? json) {
    if (json is! List) return const [];
    return [for (final punto in json) ?PuntoRuta.desdeJson(punto)];
  }

  /// `distancia_km` es `numeric`, que según el caso llega como número o como
  /// texto (lo mismo que `distancia_total_m` en `EntrenamientoService`).
  static double? _comoDouble(Object? valor) => switch (valor) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is Ruta && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Ruta($nombre, ${estado.valorDb})';
}

/// Una ruta lista para insertar: el recorrido de un entrenamiento finalizado
/// con el nombre y la descripción que le puso su autor.
///
/// Se construye con [NuevaRuta.desdeRecorrido], que es quien convierte los
/// puntos del entrenamiento en el trazado que se guarda.
@immutable
class NuevaRuta {
  const NuevaRuta({
    required this.entrenamientoId,
    required this.nombre,
    required this.trazado,
    this.descripcion,
  });

  /// El recorrido de [entrenamientoId] convertido en trazado.
  ///
  /// [puntos] son los del entrenamiento, en orden de captura; se quedan
  /// hasta [maxPuntosTrazadoRuta]. Las pausas no se marcan: quien siga la
  /// ruta no necesita saber dónde paró a tomar agua el que la grabó.
  factory NuevaRuta.desdeRecorrido({
    required String entrenamientoId,
    required String nombre,
    required List<PuntoGps> puntos,
    String? descripcion,
  }) {
    return NuevaRuta(
      entrenamientoId: entrenamientoId,
      nombre: nombre,
      descripcion: descripcion,
      trazado: trazadoDesdePuntos(puntos),
    );
  }

  final String entrenamientoId;
  final String nombre;
  final String? descripcion;
  final List<PuntoRuta> trazado;

  /// Lo que manda el cliente. Autor, nombre del autor, estado, inicio,
  /// distancia y fechas los pone la base.
  Map<String, dynamic> aSupabase() => {
    'entrenamiento_id': entrenamientoId,
    'nombre': nombre,
    // Una descripción en blanco no se manda: la columna admite nulo y
    // guardar espacios sería guardar ruido.
    'descripcion': ?_descripcionGuardable,
    'trazado': [for (final punto in trazado) punto.aJson()],
  };

  String? get _descripcionGuardable {
    final texto = descripcion?.trim();
    return texto == null || texto.isEmpty ? null : texto;
  }

  /// Convierte el recorrido de un entrenamiento en el trazado de una ruta,
  /// recortándolo a [maximo] puntos.
  ///
  /// El recorte reparte los puntos a lo largo del recorrido y conserva
  /// siempre el primero y el último: el primero es el que la base guarda
  /// como inicio de la ruta, y el último es donde termina.
  static List<PuntoRuta> trazadoDesdePuntos(
    List<PuntoGps> puntos, {
    int maximo = maxPuntosTrazadoRuta,
  }) {
    assert(maximo >= 2, 'un trazado necesita al menos dos puntos');

    final todos = [
      for (final punto in puntos)
        PuntoRuta(latitud: punto.latitud, longitud: punto.longitud),
    ];
    if (todos.length <= maximo) return todos;

    final paso = (todos.length - 1) / (maximo - 1);
    return [
      for (var i = 0; i < maximo - 1; i++) todos[(i * paso).round()],
      todos.last,
    ];
  }

  @override
  String toString() => 'NuevaRuta($nombre, ${trazado.length} puntos)';
}
