import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nuevo_reto.dart';
import '../models/reto.dart';
import '../models/reto_del_usuario.dart';
import '../models/vigencia_reto.dart';

/// Repositorio de retos que usa la app. Las pruebas lo sustituyen con
/// `overrideWithValue`.
final retosRepositoryProvider = Provider<RetosRepository>(
  (ref) => SupabaseRetosRepository(),
);

/// Se lanza cuando se intenta administrar retos sin una sesión abierta.
class SesionRequeridaParaRetosException implements Exception {
  const SesionRequeridaParaRetosException();

  @override
  String toString() =>
      'SesionRequeridaParaRetosException: no hay una sesión abierta';
}

/// Se lanza cuando Postgres rechaza la operación por Row Level Security: la
/// cuenta tiene sesión, pero no es la del administrador.
///
/// Es la barrera de verdad. La app decide qué pantallas muestra según
/// `perfiles.rol`, pero con la publishable key cualquiera puede llamar a la
/// API; si la única comprobación estuviera en Dart, no habría ninguna.
class SoloAdministradorException implements Exception {
  const SoloAdministradorException();

  @override
  String toString() =>
      'SoloAdministradorException: la cuenta no tiene rol de administrador';
}

/// Se lanza cuando la base rechaza los datos del reto.
///
/// No debería ocurrir: `BorradorReto` valida las mismas reglas antes. Si llega
/// aquí, es que las restricciones de la tabla y la validación de Dart se
/// desalinearon, y conviene que se note.
class DatosDeRetoInvalidosException implements Exception {
  const DatosDeRetoInvalidosException(this.detalle);

  final String detalle;

  @override
  String toString() => 'DatosDeRetoInvalidosException: $detalle';
}

/// Acceso a la tabla `retos`.
abstract interface class RetosRepository {
  /// Registra [reto] y devuelve la fila creada (SCRUM-143).
  ///
  /// Lo que vuelve trae el id y el estado que puso la base, no los que mandó
  /// el cliente.
  Future<Reto> crear(NuevoReto reto);

  /// Los retos del catálogo con el [estado] pedido, del más reciente al más
  /// antiguo.
  ///
  /// Es lo que necesita el criterio 1 de SCRUM-132: al crear un reto, verlo
  /// aparecer en el catálogo. Es la consulta del administrador, que ve todo
  /// lo que ha creado aunque ya no esté vigente.
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo});

  /// Los retos que un corredor puede intentar hoy (SCRUM-163): activos y con
  /// [hoy] dentro de su vigencia.
  ///
  /// Ordenados por lo que se acaba antes. Un reto diario que termina esta
  /// noche es más urgente que uno mensual al que le quedan tres semanas, y
  /// eso es lo primero que el corredor necesita ver.
  Future<List<Reto>> vigentes({required DateTime hoy});

  /// Los retos que el corredor ha activado, del más reciente al más antiguo
  /// (SCRUM-173 y SCRUM-174).
  ///
  /// Trae el reto embebido: sin su meta y su vigencia, el progreso guardado
  /// no significa nada.
  Future<List<RetoDelUsuario>> misRetos();
}

class SupabaseRetosRepository implements RetosRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseRetosRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'retos';
  static const _tablaRetosUsuario = 'retos_usuario';

  /// Suficiente para el catálogo de un proyecto de curso sin traer la tabla
  /// entera.
  static const limite = 100;

  /// Códigos de error de Postgres que hay que distinguir.
  static const _rlsDenegado = '42501';
  static const _restriccionIncumplida = '23514';

  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas que
  // nunca llegan a hablar con Supabase no necesitan inicializarlo.
  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  String _usuarioId() {
    final id =
        _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaParaRetosException();
    return id;
  }

  @override
  Future<Reto> crear(NuevoReto reto) async {
    final usuarioId = _usuarioId();

    try {
      final fila = await _cliente
          .from(_tabla)
          // `estado` no va: lo pone el default 'activo' de la tabla
          // (SCRUM-145). Si el cliente lo enviara podría nacer retirado.
          .insert({...reto.aSupabase(), 'creado_por': usuarioId})
          // Se devuelve la fila completa para conocer el id y el estado que
          // asignó la base, en vez de darlos por supuestos.
          .select()
          .single();

      return Reto.desdeSupabase(fila);
    } on PostgrestException catch (e) {
      // La policy de insert exige es_admin(); sin ese rol, Postgres responde
      // que la fila viola la seguridad a nivel de fila.
      if (e.code == _rlsDenegado) throw const SoloAdministradorException();
      if (e.code == _restriccionIncumplida) {
        throw DatosDeRetoInvalidosException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async {
    // Sin sesión, RLS no devolvería nada; se corta antes para que el error
    // diga qué pasó en vez de mostrar un catálogo vacío.
    _usuarioId();

    final filas = await _cliente
        .from(_tabla)
        .select()
        .eq('estado', estado.valorDb)
        .order('fecha_creacion', ascending: false)
        .limit(limite);

    return filas.map(Reto.desdeSupabase).toList();
  }

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async {
    final dia = VigenciaReto.aTexto(hoy);

    // El filtro de vigencia va aquí y no en la policy: RLS decide quién ve
    // qué, no qué muestra cada pantalla. La misma fila es "vigente" hoy y
    // "vencida" mañana sin que cambien los permisos.
    final filas = await _cliente
        .from(_tabla)
        .select()
        .eq('estado', EstadoReto.activo.valorDb)
        .lte('fecha_inicio', dia)
        .gte('fecha_fin', dia)
        // `ascending` explícito: en postgrest el valor por defecto de
        // `order` es descendente, así que sin esto lo que más falta hacía
        // quedaba al final.
        .order('fecha_fin', ascending: true)
        .limit(limite);

    return filas.map(Reto.desdeSupabase).toList();
  }

  @override
  Future<List<RetoDelUsuario>> misRetos() async {
    final usuarioId = _usuarioId();

    // `retos(*)` embebe el reto de la clave foránea en la misma consulta: sin
    // él habría que pedir cada reto por separado.
    //
    // El filtro por usuario es redundante con la policy, que ya limita las
    // filas a las de `auth.uid()`. Va explícito porque una consulta debe
    // decir qué pide, no confiar en que alguien la recorte por detrás.
    final filas = await _cliente
        .from(_tablaRetosUsuario)
        .select('*, retos(*)')
        .eq('usuario_id', usuarioId)
        .order('fecha_activacion', ascending: false)
        .limit(limite);

    return filas.map(RetoDelUsuario.desdeSupabase).toList();
  }
}
