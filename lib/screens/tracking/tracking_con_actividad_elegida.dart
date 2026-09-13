import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'tracking_screen.dart';
import '../../services/actividad_provider.dart';
import '../../services/entrenamiento_provider.dart';
import '../../services/recorrido_provider.dart';
import '../../widgets/traza_toast.dart';

/// Abre la pantalla del entrenamiento en curso (`TrackingScreen`, de Aaron)
/// con la actividad que el usuario eligió en los chips del inicio (SCRUM-93).
///
/// Sin configuración de inicio, por ejemplo al entrar a `/tracking` a mano sin
/// sesión, usa la actividad por defecto de la pantalla: así se puede seguir
/// abriendo para probarla mientras no exista el login.
///
/// Al finalizar, cierra el entrenamiento y abre el resumen (SCRUM-121).
class TrackingConActividadElegida extends ConsumerWidget {
  const TrackingConActividadElegida({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuracion = ref.watch(configuracionInicioProvider);
    void alFinalizar(Duration duracion) => _finalizar(context, ref, duracion);

    return configuracion == null
        ? TrackingScreen(onFinalizar: alFinalizar)
        : TrackingScreen(
            nombreActividad: configuracion.nombreActividad,
            onFinalizar: alFinalizar,
          );
  }

  /// La pantalla de Aaron ya detuvo el cronómetro e intentó guardar los
  /// puntos; falta cerrar el entrenamiento y pasar al resumen.
  Future<void> _finalizar(
    BuildContext context,
    WidgetRef ref,
    Duration duracion,
  ) async {
    final error = await ref
        .read(cierreEntrenamientoProvider)
        .finalizar(duracion: duracion, recorrido: ref.read(recorridoProvider));
    if (!context.mounted) return;

    if (error != null) {
      // Por encima de los botones, para que "Finalizar" se pueda volver a
      // tocar mientras el aviso sigue visible.
      mostrarToast(context, error, separacionInferior: 150);
      return;
    }
    // `go` y no `push`: desde el resumen no se vuelve a una actividad que ya
    // terminó.
    context.go('/resumen');
  }
}
