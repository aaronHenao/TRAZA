import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../screens/tracking/tracking_screen.dart';
import 'actividad_providers.dart';

/// Abre la pantalla del entrenamiento en curso (`TrackingScreen`, de Aaron)
/// con la actividad que el usuario eligió en los chips del inicio (SCRUM-93).
///
/// Sin configuración de inicio, por ejemplo al entrar a `/tracking` a mano sin
/// sesión, usa la actividad por defecto de la pantalla: así se puede seguir
/// abriendo para probarla mientras no exista el login.
class TrackingConActividadElegida extends ConsumerWidget {
  const TrackingConActividadElegida({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuracion = ref.watch(configuracionInicioProvider);

    return configuracion == null
        ? const TrackingScreen()
        : TrackingScreen(nombreActividad: configuracion.nombreActividad);
  }
}
