import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

import '../models/estado_permisos.dart';
import '../models/metricas_salud.dart';
import 'permisos_provider.dart';

/// Lee los datos de salud de un entrenamiento (SCRUM-79).
///
/// La app usa [SaludHealth]; las pruebas inyectan uno falso.
abstract class SaludService {
  Future<MetricasSalud> leer({required DateTime inicio, required DateTime fin});
}

/// Implementación con `health`: Health Connect en Android, Apple Health en
/// iOS. Solo lee lo que declara `tiposDatosSalud` en `permisos_service.dart`.
class SaludHealth implements SaludService {
  SaludHealth({Health? health}) : _health = health ?? Health();

  final Health _health;

  @override
  Future<MetricasSalud> leer({
    required DateTime inicio,
    required DateTime fin,
  }) async {
    await _health.configure();

    // El mismo dato puede llegar del teléfono y del reloj: se quitan repetidos.
    final lecturas = _health.removeDuplicates(
      await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.HEART_RATE,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ],
        startTime: inicio,
        endTime: fin,
      ),
    );

    List<num> valoresDe(HealthDataType tipo) => [
      for (final lectura in lecturas)
        if (lectura.type == tipo && lectura.value is NumericHealthValue)
          (lectura.value as NumericHealthValue).numericValue,
    ];

    return MetricasSalud.desdeLecturas(
      frecuencias: valoresDe(HealthDataType.HEART_RATE),
      calorias: valoresDe(HealthDataType.ACTIVE_ENERGY_BURNED),
      // Los pasos se piden aparte: el sistema ya los suma sin contar dos veces
      // los del teléfono y el reloj.
      pasos: await _health.getTotalStepsInInterval(inicio, fin),
    );
  }
}

final saludServiceProvider = Provider<SaludService>((ref) => SaludHealth());

/// Tramo de tiempo que duró un entrenamiento.
typedef VentanaEntrenamiento = ({DateTime inicio, DateTime fin});

/// Métricas de salud de un entrenamiento, o null si no hay que mostrar nada.
///
/// Sin permiso, o si el usuario eligió entrenar sin datos de salud
/// (SCRUM-83), no se leen ni se muestran.
final metricasSaludProvider = FutureProvider.autoDispose
    .family<MetricasSalud?, VentanaEntrenamiento>((ref, ventana) async {
      final permisos = ref.watch(permisosProvider);
      if (permisos.saludOmitida) return null;

      final puedeLeer = switch (permisos.salud) {
        EstadoPermiso.concedido => true,
        // iOS nunca dice si se concedió la lectura: se intenta, y si el
        // usuario lo negó simplemente no llegan datos.
        EstadoPermiso.desconocido =>
          defaultTargetPlatform == TargetPlatform.iOS,
        EstadoPermiso.denegado ||
        EstadoPermiso.bloqueado ||
        EstadoPermiso.noDisponible => false,
      };
      if (!puedeLeer) return null;

      try {
        final metricas = await ref
            .read(saludServiceProvider)
            .leer(inicio: ventana.inicio, fin: ventana.fin);
        return metricas.vacia ? null : metricas;
      } catch (error) {
        // Los datos de salud son un extra: si fallan, el resumen sale igual.
        debugPrint('No se pudieron leer los datos de salud: $error');
        return null;
      }
    });
