import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/experiencia_ganada.dart';
import 'objetivos_service.dart' show SesionRequeridaException;

/// De dónde sale la experiencia acumulada de la cuenta con la sesión abierta.
///
/// La progresión (SCRUM-178) solo la consulta: quién la suma y dónde se guarda
/// es del motor de experiencia, la historia que acredita XP al completar un
/// reto (SCRUM-192). Esta interfaz es la frontera entre las dos, para que esa
/// historia aterrice sin tocar nada de la progresión.
///
/// Las pruebas lo sustituyen con `overrideWithValue`.
final experienciaRepositoryProvider = Provider<ExperienciaRepository>(
  (ref) => SupabaseExperienciaRepository(),
);

/// Lectura de la experiencia.
///
/// Solo lectura: la XP la asigna el trigger de `0009_experiencia.sql` al
/// finalizar un entrenamiento (SCRUM-203), y el cliente no puede escribirla.
abstract interface class ExperienciaRepository {
  /// La experiencia que el corredor tiene acreditada. Nunca negativa.
  Future<int> experienciaAcumulada();

  /// La XP que dejó [entrenamientoId], o null si no se procesó (SCRUM-207).
  Future<ExperienciaDeEntrenamiento?> ganadaEn(String entrenamientoId);
}

class SupabaseExperienciaRepository implements ExperienciaRepository {
  /// [cliente] y [usuarioActual] existen para las pruebas. En la app se dejan
  /// vacíos: se usa el cliente global y el usuario de la sesión abierta.
  SupabaseExperienciaRepository({
    SupabaseClient? cliente,
    String? Function()? usuarioActual,
  }) : _clienteInyectado = cliente,
       _usuarioActual = usuarioActual;

  static const _tabla = 'experiencia_ganada';

  /// Se embebe el nombre del reto a través de `reto_usuario_id` para
  /// mostrarlo en el resumen sin otra consulta.
  static const _columnas =
      'origen, cantidad, ajuste, retos_usuario(retos(nombre))';

  // `Supabase.instance` se toca recién al usarlo, así que las pruebas que
  // nunca llegan a hablar con Supabase no necesitan inicializarlo.
  final SupabaseClient? _clienteInyectado;
  final String? Function()? _usuarioActual;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  // Sin sesión, RLS no devolvería nada; se corta antes para que el error diga
  // qué pasó en vez de mostrar cero XP.
  void _exigirSesion() {
    final id = _usuarioActual?.call() ?? _cliente.auth.currentUser?.id;
    if (id == null) throw const SesionRequeridaException();
  }

  @override
  Future<int> experienciaAcumulada() async {
    _exigirSesion();

    // La suma la hace la base: no hay un total guardado que se desincronice.
    final total = await _cliente.rpc<dynamic>('experiencia_total');
    if (total is! num) {
      throw FormatException(
        'experiencia_total devolvió algo inesperado',
        total,
      );
    }
    return total.toInt();
  }

  @override
  Future<ExperienciaDeEntrenamiento?> ganadaEn(String entrenamientoId) async {
    _exigirSesion();

    final filas = await _cliente
        .from(_tabla)
        .select(_columnas)
        .eq('entrenamiento_id', entrenamientoId);

    return ExperienciaDeEntrenamiento.desdeFilas(filas);
  }
}
