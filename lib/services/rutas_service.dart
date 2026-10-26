import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dificultad.dart';
import '../models/ruta.dart';
import '../models/ruta_cercana.dart';
import '../models/zona.dart';
// `usuarioActualProvider` vive ahí desde el foro, pero no es del foro: dice
// quién tiene la sesión abierta. Se reutiliza en vez de declarar otro, para
// que una prueba que sustituya la sesión la sustituya para toda la app.
import 'foro_service.dart' show usuarioActualProvider;

/// Repositorio de rutas que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final rutasRepositoryProvider = Provider<RutasRepository>(
  (ref) =>
      SupabaseRutasRepository(usuarioActual: ref.read(usuarioActualProvider)),
);

/// Se lanza cuando se intenta registrar una ruta sin una sesión abierta.
class SesionRequeridaParaRutasException implements Exception {
  const SesionRequeridaParaRutasException();

  @override
  String toString() =>
      'SesionRequeridaParaRutasException: no hay una sesión abierta';
}

/// Se lanza cuando la base no deja publicar una ruta de ese entrenamiento.
///
/// La policy de insert de `rutas` exige que el entrenamiento sea del usuario
/// y esté finalizado, y la clave foránea, que todavía exista. Un entrenamiento
/// ajeno, en curso, cancelado o borrado cae aquí.
class EntrenamientoNoPublicableException implements Exception {
  const EntrenamientoNoPublicableException();

  @override
  String toString() =>
      'EntrenamientoNoPublicableException: el entrenamiento no es del usuario, '
      'no está finalizado o ya no existe';
}

/// Se lanza cuando ese entrenamiento ya tiene una ruta en pie.
///
/// Nadie quiere publicar dos veces el mismo recorrido: pasa por un doble
/// toque, por reintentar un envío que en realidad funcionó, o por volver al
/// entrenamiento sin acordarse. Lo impide el índice
/// `rutas_una_por_entrenamiento` (`0031`), que deja fuera las rechazadas
/// para que se puedan corregir y volver a mandar.
class EntrenamientoYaPublicadoException implements Exception {
  const EntrenamientoYaPublicadoException();

  @override
  String toString() =>
      'EntrenamientoYaPublicadoException: ese entrenamiento ya tiene una ruta';
}

/// Se lanza cuando la cuenta no puede hacer eso con la ruta (SCRUM-363): no
/// es Runner Experto, quiere clasificar su propia ruta, o confirma una que no
/// es suya. Lo deciden `clasificar_ruta` y `confirmar_publicacion_ruta`
/// (0045).
class SinPermisoSobreRutaException implements Exception {
  const SinPermisoSobreRutaException();

  @override
  String toString() =>
      'SinPermisoSobreRutaException: la cuenta no puede hacer eso con la ruta';
}

/// Se lanza cuando la ruta ya no está en el estado que hacía falta
/// (SCRUM-363): otro experto la clasificó primero, o ya no espera la
/// confirmación de su autor.
class RutaCambioDeEstadoException implements Exception {
  const RutaCambioDeEstadoException();

  @override
  String toString() =>
      'RutaCambioDeEstadoException: la ruta ya no está en ese estado';
}

/// Se lanza cuando la base rechaza los datos de la ruta.
///
/// Las restricciones de `rutas` y el trigger `rutas_preparar` piden un nombre
/// de 1 a 120 caracteres y un trazado de al menos dos puntos con coordenadas.
/// No debería llegar aquí: la app valida lo mismo antes de enviar. Si pasa,
/// la tabla y la validación de Dart se desalinearon.
class DatosDeRutaInvalidosException implements Exception {
  const DatosDeRutaInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDeRutaInvalidosException: $detalle';
}

/// Se lanza cuando la base no deja revisar la clasificación de una ruta
/// (SCRUM-262): quien lo intenta no es Runner Experto o es su autor
/// (`puede_revisar_clasificacion`, 0042).
class SinPermisoParaRevisarException implements Exception {
  const SinPermisoParaRevisarException();

  @override
  String toString() =>
      'SinPermisoParaRevisarException: no puede revisar la clasificación de '
      'esa ruta';
}

/// Acceso a la tabla `rutas` (SCRUM-241).
abstract interface class RutasRepository {
  /// Registra [ruta] a nombre del usuario de la sesión y devuelve la fila
  /// creada.
  ///
  /// Lo que vuelve trae lo que puso la base: el nombre del autor, el estado
  /// —siempre `en_revision`, publicar manda a revisión— el punto de inicio
  /// y la distancia.
  ///
  /// Lanza [EntrenamientoNoPublicableException] si el entrenamiento no es del
  /// usuario, no está finalizado o ya no existe,
  /// [EntrenamientoYaPublicadoException] si ya tiene una ruta en pie, y
  /// [DatosDeRutaInvalidosException] si la base rechaza el nombre o el
  /// trazado.
  Future<Ruta> crear(NuevaRuta ruta);

  /// La ruta que el usuario ya publicó de [entrenamientoId], o null si no
  /// tiene ninguna.
  ///
  /// Es lo que deja al formulario decir "ya publicaste esta ruta" y llevar a
  /// verla, en vez de dejar crear una gemela y descubrirlo después. Las
  /// rechazadas no cuentan: esas se pueden corregir y volver a mandar.
  Future<Ruta?> rutaDeEntrenamiento(String entrenamientoId);

  /// Las rutas del usuario de la sesión, de la más reciente a la más
  /// antigua, en cualquier estado.
  ///
  /// En revisión, publicadas y rechazadas: es donde el autor ve en qué quedó
  /// lo que mandó (criterio 1). Sin el trazado, que un listado no dibuja.
  Future<List<Ruta>> misRutas();

  /// Las rutas que la comunidad ya puede ver, de la última publicada a la
  /// primera.
  ///
  /// Sin el trazado, que un listado no dibuja. Traen su autor y su fecha de
  /// publicación, que es lo que hay que mostrar de cada una (criterio 4), y
  /// su distancia (SCRUM-240).
  Future<List<Ruta>> publicadas();

  /// La ruta con [id] y su trazado, o null si no existe o el usuario no
  /// puede verla.
  ///
  /// Puede volver en cualquier estado: el autor ve lo suyo en revisión, el
  /// Runner Experto lo que tiene que revisar y el administrador todo. Lo
  /// publicado lo ve cualquiera.
  Future<Ruta?> ruta(String id);

  /// Las rutas publicadas que arrancan a menos de [radioKm] de unas
  /// coordenadas, de la más cercana a la más lejana (SCRUM-246).
  ///
  /// La cuenta la hace la base con `rutas_cercanas` (0037): mide hasta el
  /// punto de inicio de cada ruta y respeta RLS, así que lo que está en
  /// revisión no sale ni para su autor. Sin el trazado, como los demás
  /// listados.
  Future<List<RutaCercana>> cercanas({
    required double latitud,
    required double longitud,
    required double radioKm,
  });

  /// Las rutas publicadas cuyo nombre o creador coinciden con [termino],
  /// estén donde estén (SCRUM-254), y con [zona], también las que arrancan
  /// dentro de ella (SCRUM-255).
  ///
  /// La búsqueda la hace la base con `buscar_rutas` (0040): sin tildes ni
  /// mayúsculas, y con todas las palabras de [termino] en cualquier orden.
  /// Con [latitud] y [longitud], de la más cercana a la más lejana; sin
  /// ellas, de la más reciente a la más antigua. [termino] necesita al
  /// menos dos letras: con menos, la base lo rechaza.
  Future<List<Ruta>> buscar({
    required String termino,
    double? latitud,
    double? longitud,
    Zona? zona,
  });

  /// Las rutas ajenas en revisión que puede clasificar un Runner Experto, la
  /// más antigua primero: la que lleva más tiempo esperando (SCRUM-363).
  ///
  /// RLS solo le deja ver las en revisión a quien tiene el rol (0029). El
  /// filtro va igual: el administrador las ve todas.
  Future<List<Ruta>> porClasificar();

  /// Le asigna [dificultad] a [ruta], que pasa a esperar la confirmación de
  /// su autor, y devuelve la fila guardada (SCRUM-363).
  ///
  /// Lanza [SinPermisoSobreRutaException] si la cuenta no es Runner Experto
  /// o la ruta es suya, y [RutaCambioDeEstadoException] si ya no está en
  /// revisión.
  Future<Ruta> clasificar(Ruta ruta, Dificultad dificultad);

  /// El autor confirma la publicación de [ruta], ya clasificada, y devuelve
  /// la fila publicada (criterio 2 de SCRUM-363).
  ///
  /// Lanza [SinPermisoSobreRutaException] si no es suya y
  /// [RutaCambioDeEstadoException] si no está esperando su confirmación.
  Future<Ruta> confirmarPublicacion(Ruta ruta);

  /// Si quien tiene la sesión abierta puede revisar la clasificación de la
  /// ruta [rutaId] (SCRUM-261): es Runner Experto y no es su autor. Lo
  /// decide la base, con `puede_revisar_clasificacion` (0042).
  Future<bool> puedeRevisarClasificacion(String rutaId);

  /// Confirma la dificultad propuesta de la ruta [rutaId] y la deja marcada
  /// como revisada por quien tiene la sesión abierta (SCRUM-262, criterio 3
  /// de HU-35).
  ///
  /// Lo hace la base, con `confirmar_clasificacion`. Esa función todavía no
  /// existe: depende de que SCRUM-363 cree la dificultad, y lo que tiene que
  /// hacer está escrito en `docs/deudas.md`. Lanza
  /// [SinPermisoParaRevisarException] si la base no lo deja.
  Future<void> confirmarClasificacion(String rutaId);

  /// Reemplaza la dificultad de la ruta [rutaId] por [dificultad] y la deja
  /// marcada como revisada por quien tiene la sesión abierta: queda como su
  /// clasificación definitiva (SCRUM-263, criterio 4 de HU-35).
  ///
  /// Lo hace la base, con `corregir_clasificacion`, que todavía no existe por
  /// lo mismo que `confirmar_clasificacion` (`docs/deudas.md`). Lanza
  /// [SinPermisoParaRevisarException] si la base no lo deja.
  Future<void> corregirClasificacion(String rutaId, Dificultad dificultad);
}

/// Lee y escribe en `rutas`.
///
/// La policy de insert exige que el entrenamiento sea del usuario y esté
/// finalizado: si el insert falla por permiso, revisa eso antes que el
/// código Dart.
class SupabaseRutasRepository implements RutasRepository {
  SupabaseRutasRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const String tabla = 'rutas';

  /// Cuántas rutas se traen de una vez.
  static const limite = 100;

  /// Lo que se lee de una ruta cuando no hace falta su trazado. Pedir `*`
  /// traería cientos de coordenadas por fila para no dibujar ninguna.
  ///
  /// `miniatura` no es una columna: es un campo calculado (0038) que
  /// devuelve 32 puntos del trazado, lo justo para dibujar la ruta en
  /// pequeño en una tarjeta (SCRUM-247).
  static const _columnas =
      'id,autor_id,autor_nombre,entrenamiento_id,nombre,descripcion,'
      'distancia_km,estado,motivo_rechazo,fecha_creacion,fecha_publicacion,'
      'miniatura,dificultad';

  static const _columnasConTrazado = '$_columnas,trazado';

  /// La policy de insert no dejó crear la fila.
  static const _rlsRechazo = '42501';

  /// Una restricción de la tabla o el trigger dijo que no.
  static const _restriccionIncumplida = '23514';

  /// El entrenamiento ya no existe: la clave foránea no encuentra a quién
  /// apuntar.
  static const _sinReferencia = '23503';

  /// Ese entrenamiento ya tiene una ruta: lo dice el índice único de 0031.
  static const _duplicado = '23505';

  /// La ruta ya no está en el estado que hacía falta: lo dicen
  /// `clasificar_ruta` y `confirmar_publicacion_ruta` (0045).
  static const _cambioDeEstado = 'TZ409';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaRutasException();
    return id;
  }

  @override
  Future<Ruta> crear(NuevaRuta ruta) async {
    final usuarioId = _usuarioId();

    try {
      // Ni el nombre del autor, ni el estado, ni el inicio, ni la distancia
      // van en el insert: los pone el trigger `rutas_preparar`. Si los
      // mandara el cliente, cualquiera publicaría a nombre de otro, se
      // saltaría la revisión del experto o se inventaría sus kilómetros.
      final fila = await _cliente
          .from(tabla)
          .insert({...ruta.aSupabase(), 'autor_id': usuarioId})
          .select(_columnasConTrazado)
          .single();

      return Ruta.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      if (e.code == _restriccionIncumplida) {
        throw DatosDeRutaInvalidosException(e.message);
      }
      if (e.code == _duplicado) {
        throw const EntrenamientoYaPublicadoException();
      }
      if (e.code == _rlsRechazo || e.code == _sinReferencia) {
        throw const EntrenamientoNoPublicableException();
      }
      rethrow;
    }
  }

  @override
  Future<Ruta?> rutaDeEntrenamiento(String entrenamientoId) async {
    final usuarioId = _usuarioId();

    // Como mucho hay una: lo garantiza el índice único de 0031. Sin el
    // trazado, que esto solo contesta "sí, y es esta".
    final fila = await _cliente
        .from(tabla)
        .select(_columnas)
        .eq('autor_id', usuarioId)
        .eq('entrenamiento_id', entrenamientoId)
        .neq('estado', EstadoRuta.rechazada.valorDb)
        .maybeSingle();

    return fila == null ? null : Ruta.desdeSupabase(fila);
  }

  @override
  Future<List<Ruta>> misRutas() async {
    final usuarioId = _usuarioId();

    // El filtro por autor va aunque RLS ya decida qué se puede leer: al
    // Runner Experto y al administrador les devolvería también las de los
    // demás, y estas son "mis rutas".
    final filas = await _cliente
        .from(tabla)
        .select(_columnas)
        .eq('autor_id', usuarioId)
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(Ruta.desdeSupabase).toList();
  }

  @override
  Future<List<Ruta>> publicadas() async {
    _usuarioId();

    // El filtro por estado va aunque RLS ya oculte lo ajeno en revisión: al
    // autor le devolvería también lo suyo sin aprobar, y eso no es la
    // comunidad.
    final filas = await _cliente
        .from(tabla)
        .select(_columnas)
        .eq('estado', EstadoRuta.publicada.valorDb)
        .order('fecha_publicacion', ascending: false)
        .limit(limite);

    return filas.map(Ruta.desdeSupabase).toList();
  }

  @override
  Future<Ruta?> ruta(String id) async {
    _usuarioId();

    final fila = await _cliente
        .from(tabla)
        .select(_columnasConTrazado)
        .eq('id', id)
        .maybeSingle();

    return fila == null ? null : Ruta.desdeSupabase(fila);
  }

  @override
  Future<List<RutaCercana>> cercanas({
    required double latitud,
    required double longitud,
    required double radioKm,
  }) async {
    _usuarioId();

    // El orden y la distancia vienen hechos de la base: ordenar aquí
    // obligaría a traer todas las rutas para quedarse con las de cerca.
    final filas = await _cliente.rpc<List<dynamic>>(
      'rutas_cercanas',
      params: {
        'p_latitud': latitud,
        'p_longitud': longitud,
        'p_radio_km': radioKm,
        'p_limite': limite,
      },
    );

    return [
      for (final fila in filas)
        RutaCercana.desdeSupabase(Map<String, dynamic>.from(fila as Map)),
    ];
  }

  @override
  Future<List<Ruta>> buscar({
    required String termino,
    double? latitud,
    double? longitud,
    Zona? zona,
  }) async {
    _usuarioId();

    final filas = await _cliente.rpc<List<dynamic>>(
      'buscar_rutas',
      params: {
        'p_termino': termino,
        // Las dos o ninguna: con una sola, la base rechaza la consulta.
        if (latitud != null && longitud != null) ...{
          'p_latitud': latitud,
          'p_longitud': longitud,
        },
        if (zona != null) ...{
          'p_zona_sur': zona.sur,
          'p_zona_oeste': zona.oeste,
          'p_zona_norte': zona.norte,
          'p_zona_este': zona.este,
        },
        'p_limite': limite,
      },
    );

    // Cada fila trae además a cuánto queda del usuario, que la tarjeta no
    // muestra: solo sirvió para ordenarlas.
    return [
      for (final fila in filas)
        Ruta.desdeSupabase(Map<String, dynamic>.from(fila as Map)),
    ];
  }

  @override
  Future<List<Ruta>> porClasificar() async {
    final usuarioId = _usuarioId();

    final filas = await _cliente
        .from(tabla)
        .select(_columnas)
        .eq('estado', EstadoRuta.enRevision.valorDb)
        // Las suyas no las puede clasificar (`clasificar_ruta`, 0045).
        .neq('autor_id', usuarioId)
        .order('fecha_creacion', ascending: true)
        .limit(limite);

    return filas.map(Ruta.desdeSupabase).toList();
  }

  @override
  Future<Ruta> clasificar(Ruta ruta, Dificultad dificultad) => _cambiarEstado(
    'clasificar_ruta',
    {'p_ruta_id': ruta.id, 'p_dificultad': dificultad.valorDb},
  );

  @override
  Future<Ruta> confirmarPublicacion(Ruta ruta) =>
      _cambiarEstado('confirmar_publicacion_ruta', {'p_ruta_id': ruta.id});

  /// Llama a una de las funciones de 0045, que devuelven la fila de `rutas`
  /// como quedó, y traduce sus errores.
  Future<Ruta> _cambiarEstado(
    String funcion,
    Map<String, dynamic> parametros,
  ) async {
    _usuarioId();

    try {
      final fila = await _cliente.rpc<Map<String, dynamic>>(
        funcion,
        params: parametros,
      );
      return Ruta.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      if (e.code == _rlsRechazo) throw const SinPermisoSobreRutaException();
      if (e.code == _cambioDeEstado) throw const RutaCambioDeEstadoException();
      rethrow;
    }
  }

  @override
  Future<bool> puedeRevisarClasificacion(String rutaId) async {
    _usuarioId();

    // Una función que devuelve un solo valor llega como ese valor, sin
    // filas alrededor.
    final puede = await _cliente.rpc<dynamic>(
      'puede_revisar_clasificacion',
      params: {'p_ruta_id': rutaId},
    );
    if (puede is! bool) {
      throw FormatException(
        'puede_revisar_clasificacion devolvió algo inesperado',
        puede,
      );
    }
    return puede;
  }

  @override
  Future<void> confirmarClasificacion(String rutaId) =>
      _guardarRevision('confirmar_clasificacion', {'p_ruta_id': rutaId});

  @override
  Future<void> corregirClasificacion(String rutaId, Dificultad dificultad) =>
      _guardarRevision('corregir_clasificacion', {
        'p_ruta_id': rutaId,
        'p_dificultad': dificultad.valorDb,
      });

  /// Llama a una de las funciones de la base que guardan la revisión de una
  /// clasificación (SCRUM-262 y SCRUM-263).
  Future<void> _guardarRevision(
    String funcion,
    Map<String, Object> parametros,
  ) async {
    _usuarioId();

    try {
      await _cliente.rpc<void>(funcion, params: parametros);
    } on PostgrestException catch (e) {
      // La regla la pone la base: quien no puede revisar recibe 42501.
      if (e.code == _rlsRechazo) throw const SinPermisoParaRevisarException();
      rethrow;
    }
  }
}
