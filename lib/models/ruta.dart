import 'package:flutter/foundation.dart';

import '../services/calculadora_distancia.dart';
import 'simplificador_trazado.dart';
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

/// Cuánto del principio y del final del recorrido no se publica, en metros
/// (RNF-04).
///
/// Una ruta empieza y acaba donde vive quien la grabó. Publicar esos dos
/// puntos exactos es publicar su portal, y con varias rutas suyas la
/// coincidencia deja de ser una casualidad.
///
/// 200 m es el orden de magnitud que usan las zonas de privacidad de otras
/// apps de running: oculta el edificio y normalmente la manzana, y a una
/// ruta de 10 km le quita un 4 % del trazo. No se difumina el punto
/// —desplazarlo al azar dentro de un radio sigue delatando el barrio, y el
/// promedio de varias rutas converge al punto real—, se recorta: lo exacto
/// no sale del teléfono.
const radioPrivacidadMetros = 200.0;

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
    this.recorridoCompleto,
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

  /// Cómo se publicó su trazado (RNF-04): `true` si su autor compartió el
  /// recorrido entero, `false` si se le quitaron los extremos, y **null si
  /// no consta** —las rutas anteriores a RNF-04, y las que llegan de
  /// `rutas_cercanas` o `buscar_rutas`, que no devuelven esta columna—.
  ///
  /// No afirmar nada es distinto de afirmar que se recortó: por eso null no
  /// se trata como `false`.
  final bool? recorridoCompleto;

  /// Si hay que avisar de que el trazo no llega a los extremos reales.
  /// Solo cuando consta que se recortó.
  bool get trazoRecortado => recorridoCompleto == false;

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
      // Ausente en lo que devuelven `rutas_cercanas` y `buscar_rutas`, que
      // listan con una lista fija de columnas: ahí queda en null, que es
      // "no consta", y los listados no muestran la nota.
      recorridoCompleto: fila['recorrido_completo'] as bool?,
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
    this.recorridoCompleto = false,
  });

  final String entrenamientoId;

  /// El recorrido del entrenamiento, tal como lo grabó el GPS.
  final List<PuntoGps> puntos;

  final String nombre;
  final String descripcion;

  /// Si su autor eligió publicar el recorrido entero, con sus extremos
  /// reales (RNF-04).
  ///
  /// Falso por defecto: la privacidad no se pide, se da. Quien quiera
  /// compartir de dónde sale tiene que decirlo a propósito.
  final bool recorridoCompleto;

  BorradorRuta copyWith({
    String? nombre,
    String? descripcion,
    bool? recorridoCompleto,
  }) => BorradorRuta(
    entrenamientoId: entrenamientoId,
    puntos: puntos,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion ?? this.descripcion,
    recorridoCompleto: recorridoCompleto ?? this.recorridoCompleto,
  );

  /// Cuánto se le quita a cada extremo al publicar: nada si se publica el
  /// recorrido completo.
  double get radioPrivacidad => recorridoCompleto ? 0 : radioPrivacidadMetros;

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
    } else if (NuevaRuta.trazadoDesdePuntos(
          puntos,
          radioPrivacidad: radioPrivacidad,
        ).length <
        2) {
      // Al quitar los extremos privados (RNF-04) no queda camino. Pasa con
      // un recorrido más corto que los dos radios, o que da vueltas sin
      // alejarse. Se dice qué hacer, no solo que no se puede: publicar el
      // recorrido completo también lo resuelve, y el interruptor está ahí
      // mismo.
      final metros = radioPrivacidadMetros.round();
      errores[CampoRuta.trazado] =
          'Por privacidad no publicamos los primeros ni los últimos $metros m '
          'del recorrido, y a este no le queda trazo después de quitarlos. '
          'Publica un entrenamiento más largo o que se aleje más del punto de '
          'partida.';
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
      trazado: NuevaRuta.trazadoDesdePuntos(
        puntos,
        radioPrivacidad: radioPrivacidad,
      ),
      recorridoCompleto: recorridoCompleto,
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
    required this.recorridoCompleto,
    this.descripcion,
  });

  final String entrenamientoId;
  final String nombre;
  final String? descripcion;
  final List<PuntoRuta> trazado;

  /// Si [trazado] es el recorrido entero o se le quitaron los extremos
  /// (RNF-04). Va a la base para que el detalle sepa si avisar.
  final bool recorridoCompleto;

  /// Lo que manda el cliente. Autor, nombre del autor, estado, inicio,
  /// distancia y fechas los pone la base.
  Map<String, dynamic> aSupabase() => {
    'entrenamiento_id': entrenamientoId,
    'nombre': nombre,
    // Sin descripción no se manda la clave: la columna admite nulo y
    // guardar una cadena vacía sería guardar ruido.
    'descripcion': ?descripcion,
    'trazado': [for (final punto in trazado) punto.aJson()],
    'recorrido_completo': recorridoCompleto,
  };

  /// Convierte el recorrido de un entrenamiento en el trazado de una ruta:
  /// primero quita los extremos privados, después lo simplifica conservando
  /// su forma y sin pasar de [maximo] puntos (RNF-06).
  ///
  /// **Ese orden importa.** Si se simplificara antes de recortar, el recorte
  /// trabajaría sobre puntos ya separados entre sí y dejaría fuera más o
  /// menos recorrido según lo largo que fuera. Recortando primero, lo que
  /// se publica siempre empieza y acaba a la misma distancia real de donde
  /// empezó y acabó de verdad.
  ///
  /// La distancia de la ruta no sale de aquí: la copia un trigger de
  /// `entrenamientos.distancia_total_m` (`0030`, `0045`), medida al correr
  /// sobre la traza completa. Simplificar no la cambia (SCRUM-305).
  ///
  /// Puede devolver menos de dos puntos: una ruta más corta que los dos
  /// radios se queda sin nada que publicar. Quien la pida tiene que
  /// comprobarlo ([BorradorRuta.errores] lo hace).
  ///
  /// Las pausas no se marcan: quien siga la ruta no necesita saber dónde
  /// paró a tomar agua el que la grabó.
  static List<PuntoRuta> trazadoDesdePuntos(
    List<PuntoGps> puntos, {
    int maximo = maxPuntosTrazado,
    double radioPrivacidad = radioPrivacidadMetros,
  }) {
    final publicos = sinExtremosPrivados(puntos, radio: radioPrivacidad);
    // Sin cortes: las pausas no se marcan en una ruta publicada, así que
    // el trazado es una sola línea.
    final simplificados = simplificarRecorrido(publicos, maximo: maximo).puntos;
    return [
      for (final punto in simplificados)
        PuntoRuta(latitud: punto.latitud, longitud: punto.longitud),
    ];
  }

  /// [puntos] sin los que estén a menos de [radio] metros de donde empezó o
  /// terminó el recorrido (RNF-04).
  ///
  /// Se mide contra el primer y el último punto **originales**, no contra el
  /// anterior: lo que se quita es un círculo alrededor de cada extremo, no
  /// una cuenta de metros recorridos. Así, dar vueltas cerca de casa al
  /// empezar no deja un trozo del trazo pegado a ella.
  ///
  /// Devuelve una lista vacía si no queda nada fuera de los dos círculos.
  static List<PuntoGps> sinExtremosPrivados(
    List<PuntoGps> puntos, {
    double radio = radioPrivacidadMetros,
  }) {
    if (puntos.length < 2 || radio <= 0) return [...puntos];

    final inicio = puntos.first;
    final fin = puntos.last;

    bool esPublico(PuntoGps punto) =>
        CalculadoraDistancia.haversineMetros(
              inicio.latitud,
              inicio.longitud,
              punto.latitud,
              punto.longitud,
            ) >=
            radio &&
        CalculadoraDistancia.haversineMetros(
              fin.latitud,
              fin.longitud,
              punto.latitud,
              punto.longitud,
            ) >=
            radio;

    return [
      for (final punto in puntos)
        if (esPublico(punto)) punto,
    ];
  }

  @override
  String toString() => 'NuevaRuta($nombre, ${trazado.length} puntos)';
}
