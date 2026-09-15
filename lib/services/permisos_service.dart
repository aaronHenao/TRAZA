import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/estado_permisos.dart';

/// Habla con el sistema operativo para consultar y pedir permisos.
///
/// La app usa [PermisosGeolocator]; las pruebas inyectan uno falso.
abstract class PermisosService {
  /// Estado actual, sin mostrar nada al usuario.
  Future<EstadoPermiso> estadoUbicacion();

  /// Muestra la ventana del sistema si todavía se puede preguntar.
  Future<EstadoPermiso> solicitarUbicacion();

  /// Abre los ajustes de la app, único camino cuando está [EstadoPermiso.bloqueado].
  Future<void> abrirAjustes();
}

/// Implementación con `geolocator`, el mismo paquete que registra el recorrido.
///
/// Solo pide la ubicación "mientras la app está abierta": el entrenamiento lo
/// inicia el usuario y sigue con el servicio en primer plano, así que no hace
/// falta la de segundo plano (que Play Store revisa aparte).
class PermisosGeolocator implements PermisosService {
  const PermisosGeolocator();

  @override
  Future<EstadoPermiso> estadoUbicacion() async =>
      _convertir(await Geolocator.checkPermission());

  @override
  Future<EstadoPermiso> solicitarUbicacion() async =>
      _convertir(await Geolocator.requestPermission());

  @override
  Future<void> abrirAjustes() => Geolocator.openAppSettings();

  static EstadoPermiso _convertir(LocationPermission permiso) {
    return switch (permiso) {
      LocationPermission.always ||
      LocationPermission.whileInUse => EstadoPermiso.concedido,
      LocationPermission.deniedForever => EstadoPermiso.bloqueado,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => EstadoPermiso.denegado,
    };
  }
}

final permisosServiceProvider = Provider<PermisosService>(
  (ref) => const PermisosGeolocator(),
);
