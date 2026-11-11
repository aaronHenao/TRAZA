import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recorrido_local.dart';
import 'almacen_recorrido.dart';
import 'mapa_progresion_provider.dart';
import 'recorrido_provider.dart' show repositorioPuntosGpsProvider;
import 'rutas_oficiales_service.dart';

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
  /// Lo que falle por red se queda en el teléfono con `motivoSinEnviar` y se
  /// reintenta en el próximo arranque. Lo que la base rechaza —el
  /// entrenamiento no existe o no es de esta cuenta— se anota con
  /// `motivoRechazado`, queda `rechazado` y no se reintenta solo: lo decide
  /// la persona desde la pantalla de sincronización (Drift, Desarrollo
  /// Móvil).
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
      if (await _subir(entrenamientoId)) {
        subidos++;
        await _verificarRuta(entrenamientoId);
      }
    }
    return subidos;
  }

  /// Con el recorrido entero en la base, si se corría una ruta oficial, la
  /// base vuelve a medir si se completó (rutas oficiales, etapa 4): al
  /// cerrar faltaban estos puntos. Si falla, el recorrido sigue contando
  /// como subido; el resumen lo vuelve a preguntar al abrirse.
  Future<void> _verificarRuta(String entrenamientoId) async {
    try {
      final verificacion = await _ref
          .read(rutasOficialesRepositoryProvider)
          .verificar(entrenamientoId);
      // Si la completó y el mapa está abierto, que avance. Cerrado, se lee
      // al entrar a su pestaña.
      if ((verificacion?.completada ?? false) &&
          _ref.exists(mapaProgresionProvider)) {
        _ref.invalidate(mapaProgresionProvider);
      }
    } catch (error) {
      debugPrint('No se pudo verificar la ruta de $entrenamientoId: $error');
    }
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
        // Reintentarlo no lo va a arreglar, pero tampoco se borra: se anota
        // por qué, y la persona decide desde la pantalla de sincronización
        // (Drift, Desarrollo Móvil).
        debugPrint(
          'La base rechazó el recorrido $entrenamientoId (${error.code})',
        );
        await _anotar(
          entrenamientoId,
          RecorridoLocal.motivoRechazado,
          rechazado: true,
        );
        return false;
      }
      debugPrint('No se pudo subir el recorrido $entrenamientoId: $error');
      await _anotar(entrenamientoId, RecorridoLocal.motivoSinEnviar);
      return false;
    } catch (error) {
      debugPrint('No se pudo subir el recorrido $entrenamientoId: $error');
      await _anotar(entrenamientoId, RecorridoLocal.motivoSinEnviar);
      return false;
    }
  }

  /// El motivo es un texto fijo, nunca el error crudo: puede traer datos de
  /// la fila. Si ni eso se puede guardar, el recorrido sigue igual.
  Future<void> _anotar(
    String entrenamientoId,
    String motivo, {
    bool rechazado = false,
  }) async {
    try {
      await _ref
          .read(almacenRecorridoProvider)
          .registrarError(entrenamientoId, motivo, rechazado: rechazado);
    } catch (error) {
      debugPrint('No se pudo anotar el motivo del recorrido: $error');
    }
  }
}
