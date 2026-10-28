import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'almacen_recorrido.dart';
import 'recorrido_provider.dart' show repositorioPuntosGpsProvider;

/// Sube lo que quedó sin enviar de recorridos anteriores (SCRUM-292).
///
/// Durante la actividad los puntos se envían por lotes, pero si la red no
/// volvió antes de cerrar la app, lo último se queda en disco. Sin esto se
/// quedaría ahí para siempre: es lo que cierra la deuda.
///
/// Se dispara al abrir la app, cuando ya hay sesión: la policy de
/// `puntos_gps` comprueba que el entrenamiento sea del usuario.
final reenvioRecorridosProvider = FutureProvider<int>(
  (ref) => ReenvioRecorridos(ref).reintentar(),
);

class ReenvioRecorridos {
  const ReenvioRecorridos(this._ref);

  final Ref _ref;

  /// Quien lo intentó no tiene permiso sobre ese entrenamiento.
  static const _rlsDenegado = '42501';

  /// El entrenamiento ya no existe: la clave foránea no encuentra a quién
  /// apuntar.
  static const _sinReferencia = '23503';

  /// Intenta subir todos los recorridos pendientes. Devuelve cuántos
  /// quedaron completos.
  ///
  /// Lo que falle por red se queda en disco y se reintenta en el próximo
  /// arranque. Lo que falle porque ya no tiene sentido —el entrenamiento
  /// no existe o no es de este usuario— se borra: reintentarlo cada vez no
  /// lo va a arreglar.
  Future<int> reintentar() async {
    final almacen = _ref.read(almacenRecorridoProvider);

    final List<String> pendientes;
    try {
      pendientes = await almacen.conPendientes();
    } catch (error) {
      debugPrint('No se pudo mirar si hay recorridos sin subir: $error');
      return 0;
    }

    var subidos = 0;
    for (final entrenamientoId in pendientes) {
      if (await _subir(entrenamientoId)) subidos++;
    }
    return subidos;
  }

  Future<bool> _subir(String entrenamientoId) async {
    final almacen = _ref.read(almacenRecorridoProvider);
    try {
      final puntos = await almacen.pendientes(entrenamientoId);
      if (puntos.isNotEmpty) {
        await _ref
            .read(repositorioPuntosGpsProvider)
            .guardarLote(entrenamientoId: entrenamientoId, puntos: puntos);
      }
      // Este recorrido ya no crece: su actividad terminó en otra sesión.
      await almacen.olvidar(entrenamientoId);
      debugPrint(
        'Recorrido $entrenamientoId subido al arrancar: '
        '${puntos.length} puntos',
      );
      return true;
    } on PostgrestException catch (error) {
      if (error.code == _rlsDenegado || error.code == _sinReferencia) {
        debugPrint(
          'El recorrido $entrenamientoId ya no se puede subir (${error.code}): '
          'se descarta',
        );
        await _olvidarSinFallar(entrenamientoId);
        return false;
      }
      debugPrint('No se pudo subir el recorrido $entrenamientoId: $error');
      return false;
    } catch (error) {
      debugPrint('No se pudo subir el recorrido $entrenamientoId: $error');
      return false;
    }
  }

  Future<void> _olvidarSinFallar(String entrenamientoId) async {
    try {
      await _ref.read(almacenRecorridoProvider).olvidar(entrenamientoId);
    } catch (error) {
      debugPrint('No se pudo borrar el recorrido descartado: $error');
    }
  }
}
