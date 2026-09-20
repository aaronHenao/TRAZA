import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart';

import '../models/estado_permisos.dart';

/// Habla con el sistema operativo para consultar y pedir permisos.
///
/// La app usa [PermisosDispositivo]; las pruebas inyectan uno falso.
abstract class PermisosService {
  /// Estado actual, sin mostrar nada al usuario.
  Future<EstadoPermiso> estadoUbicacion();

  /// Muestra la ventana del sistema si todavía se puede preguntar.
  Future<EstadoPermiso> solicitarUbicacion();

  Future<EstadoPermiso> estadoSalud();

  /// Abre Apple Health o Health Connect para que el usuario elija qué datos
  /// comparte.
  Future<EstadoPermiso> solicitarSalud();

  /// Lleva a la tienda para instalar Health Connect (solo Android).
  Future<void> instalarProveedorSalud();

  /// Abre los ajustes de la app, único camino cuando está [EstadoPermiso.bloqueado].
  Future<void> abrirAjustes();
}

/// Datos de salud que se leen durante el entrenamiento. Solo lectura: la app
/// muestra lo que midió el reloj o el teléfono, no escribe nada.
///
/// Si se agrega uno, también va su permiso `READ_` en el AndroidManifest.
const tiposDatosSalud = [
  HealthDataType.HEART_RATE,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.STEPS,
];

/// Implementación real: `geolocator` para la ubicación (el mismo paquete que
/// registra el recorrido) y `health` para Apple Health y Health Connect.
class PermisosDispositivo implements PermisosService {
  PermisosDispositivo({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _saludConfigurada = false;

  // ---------------------------------------------------------------- Ubicación

  /// Solo "mientras la app está abierta": el entrenamiento lo inicia el
  /// usuario y sigue con el servicio en primer plano, así que no hace falta la
  /// de segundo plano (que Play Store revisa aparte).
  @override
  Future<EstadoPermiso> estadoUbicacion() async =>
      _convertirUbicacion(await Geolocator.checkPermission());

  @override
  Future<EstadoPermiso> solicitarUbicacion() async =>
      _convertirUbicacion(await Geolocator.requestPermission());

  static EstadoPermiso _convertirUbicacion(LocationPermission permiso) {
    return switch (permiso) {
      LocationPermission.always ||
      LocationPermission.whileInUse => EstadoPermiso.concedido,
      LocationPermission.deniedForever => EstadoPermiso.bloqueado,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => EstadoPermiso.denegado,
    };
  }

  // ------------------------------------------------------------------- Salud

  static final _lectura = List.filled(
    tiposDatosSalud.length,
    HealthDataAccess.READ,
  );

  @override
  Future<EstadoPermiso> estadoSalud() async {
    if (!await _saludDisponible()) return EstadoPermiso.noDisponible;
    final concedido = await _health.hasPermissions(
      tiposDatosSalud,
      permissions: _lectura,
    );
    // iOS devuelve null: por privacidad no dice si se negó la lectura.
    return switch (concedido) {
      true => EstadoPermiso.concedido,
      false => EstadoPermiso.denegado,
      null => EstadoPermiso.desconocido,
    };
  }

  @override
  Future<EstadoPermiso> solicitarSalud() async {
    if (!await _saludDisponible()) return EstadoPermiso.noDisponible;
    // En iOS devuelve true aunque el usuario apague todo: significa "ya se
    // preguntó". Si no hay datos, el resumen simplemente no los muestra.
    final concedido = await _health.requestAuthorization(
      tiposDatosSalud,
      permissions: _lectura,
    );
    return concedido ? EstadoPermiso.concedido : EstadoPermiso.denegado;
  }

  @override
  Future<void> instalarProveedorSalud() => _health.installHealthConnect();

  Future<bool> _saludDisponible() async {
    // El paquete usa `dart:io`, que no existe en web.
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    if (!_saludConfigurada) {
      await _health.configure();
      _saludConfigurada = true;
    }
    return _health.isHealthConnectAvailable();
  }

  // ----------------------------------------------------------------- Ajustes

  @override
  Future<void> abrirAjustes() => Geolocator.openAppSettings();
}

final permisosServiceProvider = Provider<PermisosService>(
  (ref) => PermisosDispositivo(),
);
