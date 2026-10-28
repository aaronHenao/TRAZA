import 'package:flutter/foundation.dart';

import 'dificultad.dart';
import 'punto_gps.dart';

/// En qué situación está una ruta de la comunidad.
///
/// Los nombres coinciden con la restricción `estado in (...)` de la tabla
/// `rutas` (`0029_rutas.sql`, ampliada en `0045_clasificacion_de_rutas.sql`).
enum EstadoRuta {
  /// Recién publicada: espera la revisión del administrador (SCRUM-321).
  /// Solo la ven su autor y el administrador.
  enRevision('en_revision'),

  /// El administrador la aprobó: espera a que un Runner Experto le asigne la
  /// dificultad (criterio 1 de SCRUM-363). Solo la ven su autor, los
  /// expertos y el administrador.
  revisionExperto('revision_experto'),

  /// Clasificada y confirmada por su autor: visible para toda la comunidad.
  publicada('publicada'),

  /// El administrador o el experto no la aprobó. La ve su autor con el
  /// motivo.
  rechazada('rechazada'),

  /// Un Runner Experto ya le asignó la dificultad: espera a que su autor
  /// confirme la publicación (criterio 2 de SCRUM-363).
  clasificada('clasificada'),

  /// Le faltan datos para clasificarla (la distancia): quedó registrada con
  /// la dificultad pendiente y no llega a los expertos (criterio 3 de
  /// SCRUM-363).
  datosIncompletos('datos_incompletos');

  const EstadoRuta(this.valorDb);

  final String valorDb;

  /// Cómo se le dice al autor en qué va su ruta (SCRUM-363). Lo usan el
  /// detalle y la pantalla de publicar, para que digan lo mismo.
  String get etiqueta => switch (this) {
    enRevision => 'Pendiente de revisión del administrador',
    revisionExperto => 'Pendiente de revisión del Runner Experto',
    publicada => 'Publicada',
    rechazada => 'Rechazada',
    clasificada => 'Lista para publicar',
    datosIncompletos => 'Dificultad pendiente',
  };

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
    this.miniatura = const [],
    this.distanciaKm,
    this.dificultad,
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

  /// Unos pocos puntos del trazado, repartidos a lo largo del recorrido y
  /// con la partida y la llegada, para dibujar la ruta en pequeño en un
  /// listado sin traer el trazado entero (SCRUM-247). Los calcula la base
  /// (`miniatura`, 0038). Vacía si la consulta no la pidió.
  final List<PuntoRuta> miniatura;

  /// Cuántos km mide, o null si no está registrada (criterio 4 de
  /// SCRUM-240). La calcula la base al guardar la ruta.
  final double? distanciaKm;

  /// La que le asignó un Runner Experto (SCRUM-363), o null si todavía no
  /// tiene: "Sin clasificar".
  final Dificultad? dificultad;

  /// Por qué el administrador o el experto no la aprobó (SCRUM-321). Null
  /// mientras no la rechacen.
  final String? motivoRechazo;

  /// Cuándo quedó publicada, para mostrarlo junto al autor (criterio 4).
  /// Null hasta que se apruebe.
  final DateTime? fechaPublicacion;

  bool get publicada => estado == EstadoRuta.publicada;

  /// Si se le puede mostrar la distancia a alguien (criterio 4 de
  /// SCRUM-240: cuando no, hay que avisar).
  bool get tieneDistancia => distanciaKm != null;

  /// Si [usuarioId], con o sin el rol de Runner Experto según [esExperto],
  /// puede asignarle la dificultad: el administrador ya la aprobó y no es
  /// suya (SCRUM-363 + SCRUM-321).
  ///
  /// Lo mismo exige `clasificar_ruta` (0048); aquí solo decide si se ofrece.
  bool clasificablePor(String? usuarioId, {required bool esExperto}) =>
      esExperto &&
      usuarioId != null &&
      usuarioId != autorId &&
      estado == EstadoRuta.revisionExperto;

  /// Si [usuarioId] puede confirmar su publicación: es el autor y un experto
  /// ya la clasificó (criterio 2 de SCRUM-363).
  bool publicablePor(String? usuarioId) =>
      usuarioId != null &&
      usuarioId == autorId &&
      estado == EstadoRuta.clasificada;

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
      miniatura: trazadoDesdeJson(fila['miniatura']),
      distanciaKm: _comoDouble(fila['distancia_km']),
      dificultad: Dificultad.desdeDb(fila['dificultad']),
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

/// Campos del formulario de publicación de una ruta.
///
/// El criterio 3 pide indicar *la información que hace falta*: por eso los
/// errores se devuelven por campo.
enum CampoRuta { nombre, descripcion, trazado }

/// Cuánto puede medir el nombre. Los mismos límites están en las
/// restricciones de `rutas` (`0029_rutas.sql`).
const maxCaracteresNombreRuta = 120;

/// Cuánto puede medir la descripción.
const maxCaracteresDescripcionRuta = 2000;

/// Lo que el usuario lleva escrito sobre el recorrido que quiere publicar,
/// todavía sin validar.
///
/// El trazado no se escribe: sale del entrenamiento. Lo que se valida de él
/// es que haya recorrido que publicar.
@immutable
class BorradorRuta {
  const BorradorRuta({
    required this.entrenamientoId,
    required this.puntos,
    this.nombre = '',
    this.descripcion = '',
  });

  final String entrenamientoId;

  /// El recorrido del entrenamiento, tal como lo grabó el GPS.
  final List<PuntoGps> puntos;

  final String nombre;
  final String descripcion;

  BorradorRuta copyWith({String? nombre, String? descripcion}) => BorradorRuta(
    entrenamientoId: entrenamientoId,
    puntos: puntos,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion ?? this.descripcion,
  );

  /// Qué le falta o qué está mal, por campo. Vacío si se puede publicar.
  ///
  /// La tabla repite estas reglas y es la última palabra; aquí existen para
  /// que el usuario sepa qué corregir antes de que la base lo rechace.
  Map<CampoRuta, String> get errores {
    final errores = <CampoRuta, String>{};

    // Una cadena de espacios no es un nombre.
    final nombre = this.nombre.trim();
    if (nombre.isEmpty) {
      errores[CampoRuta.nombre] = 'Ponle un nombre a tu ruta.';
    } else if (nombre.length > maxCaracteresNombreRuta) {
      errores[CampoRuta.nombre] =
          'El nombre no puede superar $maxCaracteresNombreRuta caracteres.';
    }

    if (descripcion.trim().length > maxCaracteresDescripcionRuta) {
      errores[CampoRuta.descripcion] =
          'La descripción no puede superar $maxCaracteresDescripcionRuta '
          'caracteres.';
    }

    // Un punto solo no es un camino que alguien pueda seguir, y dos lecturas
    // en la misma coordenada son un entrenamiento sin recorrido: el GPS
    // encendido con el corredor quieto.
    if (puntos.length < 2 ||
        puntos.every((punto) => punto.mismaCoordenadaQue(puntos.first))) {
      errores[CampoRuta.trazado] =
          'Este entrenamiento no tiene un recorrido que publicar.';
    }

    return errores;
  }

  bool get esValido => errores.isEmpty;

  /// La ruta lista para enviar, o null si el borrador tiene errores.
  ///
  /// Devolver null es lo que impide registrar una ruta inválida: quien quiera
  /// crearla tiene que pasar por aquí.
  NuevaRuta? aNuevaRuta() {
    if (!esValido) return null;

    final descripcion = this.descripcion.trim();
    return NuevaRuta._(
      entrenamientoId: entrenamientoId,
      nombre: nombre.trim(),
      descripcion: descripcion.isEmpty ? null : descripcion,
      trazado: NuevaRuta.trazadoDesdePuntos(puntos),
    );
  }
}

/// Una ruta validada, lista para insertar: el recorrido de un entrenamiento
/// finalizado con el nombre y la descripción que le puso su autor.
///
/// Solo se obtiene de [BorradorRuta.aNuevaRuta].
@immutable
class NuevaRuta {
  const NuevaRuta._({
    required this.entrenamientoId,
    required this.nombre,
    required this.trazado,
    this.descripcion,
  });

  final String entrenamientoId;
  final String nombre;
  final String? descripcion;
  final List<PuntoRuta> trazado;

  /// Lo que manda el cliente. Autor, nombre del autor, estado, inicio,
  /// distancia y fechas los pone la base.
  Map<String, dynamic> aSupabase() => {
    'entrenamiento_id': entrenamientoId,
    'nombre': nombre,
    // Sin descripción no se manda la clave: la columna admite nulo y
    // guardar una cadena vacía sería guardar ruido.
    'descripcion': ?descripcion,
    'trazado': [for (final punto in trazado) punto.aJson()],
  };

  /// Convierte el recorrido de un entrenamiento en el trazado de una ruta,
  /// recortándolo a [maximo] puntos.
  ///
  /// El recorte reparte los puntos a lo largo del recorrido y conserva
  /// siempre el primero y el último: el primero es el que la base guarda
  /// como inicio de la ruta, y el último es donde termina.
  ///
  /// Las pausas no se marcan: quien siga la ruta no necesita saber dónde
  /// paró a tomar agua el que la grabó.
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
