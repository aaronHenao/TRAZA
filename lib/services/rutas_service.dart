import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ruta.dart';
import '../models/ruta_cercana.dart';
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
  static const _columnas =
      'id,autor_id,autor_nombre,entrenamiento_id,nombre,descripcion,'
      'distancia_km,estado,motivo_rechazo,fecha_creacion,fecha_publicacion';

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
}
