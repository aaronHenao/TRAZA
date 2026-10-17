import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notificacion.dart';
import 'cambios_notificaciones.dart';
import 'foro_service.dart' show usuarioActualProvider;
import 'notificaciones_service.dart';

/// Las notificaciones del usuario, para la bandeja.
///
/// `autoDispose` a propósito: los avisos llegan cuando el usuario no está
/// mirando, así que una lista que se pide una vez y se guarda para toda la
/// sesión de la app enseñaría los de hace una hora. Al salir de la bandeja se
/// descarta, y al entrar se vuelve a preguntar.
final misNotificacionesProvider =
    FutureProvider.autoDispose<List<Notificacion>>(
      (ref) => ref.read(notificacionesRepositoryProvider).mias(),
    );

/// Cuántas tiene sin leer, para el contador de la campana.
///
/// También `autoDispose`, por lo mismo: así la campana vuelve a contar cada
/// vez que se vuelve a la portada, en vez de quedarse con el número que
/// había al abrir la app.
///
/// Si la consulta falla devuelve cero en vez de propagar el error: la portada
/// no se puede quedar sin pintar porque el contador de un aviso no cargue.
final notificacionesSinLeerProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  try {
    return await ref.read(notificacionesRepositoryProvider).sinLeer();
  } catch (error) {
    debugPrint('No se pudo contar las notificaciones sin leer: $error');
    return 0;
  }
});

/// Cuánto se espera después de un aviso antes de recargar: si llegan varios
/// seguidos, se resuelven con una sola consulta.
const esperaCambiosNotificaciones = Duration(milliseconds: 500);

/// Escucha las notificaciones que le llegan al usuario mientras haya una
/// pantalla que las mire: la campana de la portada o la bandeja.
///
/// Lo que llega solo avisa: se vuelve a consultar, así lo que se muestra pasa
/// por las policies de select. También recarga al volver la app a primer
/// plano, por si se aprobó una ruta mientras estaba detrás.
final notificacionesEnVivoProvider = Provider.autoDispose<void>((ref) {
  final usuario = ref.read(usuarioActualProvider)();
  if (usuario == null) return;

  Timer? espera;
  void recargar() {
    espera?.cancel();
    // Por el contenedor y no por `ref`: así solo se recarga lo que alguien
    // está mirando. `ref.invalidate` montaría el otro provider en modo debug
    // y lo consultaría sin que nadie lo mire.
    espera = Timer(esperaCambiosNotificaciones, () {
      ref.container
        ..invalidate(notificacionesSinLeerProvider)
        ..invalidate(misNotificacionesProvider);
    });
  }

  final suscripcion = ref
      .read(fuenteCambiosNotificacionesProvider)
      .de(usuario)
      .listen((_) => recargar());
  final ciclo = AppLifecycleListener(onResume: recargar);

  ref.onDispose(() {
    espera?.cancel();
    suscripcion.cancel();
    ciclo.dispose();
  });
});

/// Marcar la bandeja como vista.
final bandejaNotificacionesProvider = Provider<BandejaNotificaciones>(
  BandejaNotificaciones.new,
);

class BandejaNotificaciones {
  const BandejaNotificaciones(this._ref);

  final Ref _ref;

  /// Marca como leídas las que quedaban sin leer y apaga el contador.
  ///
  /// No se invalida [misNotificacionesProvider] a propósito: la lista en
  /// pantalla sigue mostrando cuáles estaban sin leer hasta que el usuario
  /// salga, que es lo que le deja ver qué era nuevo. Lo que se apaga es la
  /// campana.
  ///
  /// Si falla no se avisa de nada: el usuario vino a leer sus avisos, y un
  /// error marcando lo leído no es algo que pueda arreglar. Como mucho la
  /// campana sigue encendida.
  Future<void> marcarVistas() async {
    try {
      await _ref.read(notificacionesRepositoryProvider).marcarTodasLeidas();
      _ref.invalidate(notificacionesSinLeerProvider);
    } catch (error) {
      debugPrint('No se pudo marcar las notificaciones como leídas: $error');
    }
  }
}
