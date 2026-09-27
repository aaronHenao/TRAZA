import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_permisos.dart';
import '../services/permisos_provider.dart';
import '../theme/app_colors.dart';

/// Ofrece el permiso de datos de salud justo antes de iniciar (SCRUM-131,
/// criterio 3).
///
/// Si falta, muestra [VentanaPermisoSalud] cada vez que el usuario va a
/// empezar. Si lo concede, el resumen mostrará sus datos de salud; si no, la
/// actividad arranca igual, sin ellos.
///
/// Devuelve `true` si se puede iniciar, y `false` si el usuario cerró la
/// ventana sin elegir (con "atrás"): todavía no quiere empezar.
///
/// Se llama antes de crear nada, así que no deja entrenamientos a medias. Lo
/// usa el entrenamiento libre; los retos y las rutas deben llamarlo igual antes
/// de arrancar.
Future<bool> ofrecerPermisoSalud(BuildContext context, WidgetRef ref) async {
  final permisos = ref.read(permisosProvider.notifier);
  // Si todavía no se le preguntó al sistema, `desconocido` no significa que
  // falte.
  if (!ref.read(permisosProvider).consultado) await permisos.actualizar();
  if (!context.mounted) return false;

  // Sin Health Connect no hay de dónde leer: preguntar no serviría de nada.
  final salud = ref.read(permisosProvider).salud;
  if (salud == EstadoPermiso.concedido ||
      salud == EstadoPermiso.noDisponible) {
    return true;
  }

  final aceptar = await showDialog<bool>(
    context: context,
    // Un toque fuera por accidente no debe decidir por el usuario.
    barrierDismissible: false,
    builder: (_) => const VentanaPermisoSalud(),
  );
  if (aceptar == null) return false;

  if (aceptar) {
    final resultado = await permisos.solicitarSalud();
    if (resultado == EstadoPermiso.concedido) return true;
  }
  // No lo concedió: entrena igual, sin datos de salud en el resumen ni en la
  // foto.
  permisos.omitirSalud();
  return true;
}

/// La ventana que explica para qué se usan los datos de salud y pide
/// concederlos. Devuelve `true` con "Aceptar" y `false` con "Continuar sin
/// datos de salud".
class VentanaPermisoSalud extends StatelessWidget {
  const VentanaPermisoSalud({super.key});

  static const titulo = '¿Registrar tus datos de salud?';
  static const aceptar = 'Aceptar';
  static const continuarSin = 'Continuar sin datos de salud';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.secondaryTint,
        ),
        child: const Icon(
          Icons.favorite_outline,
          size: 26,
          color: AppColors.secondaryDark,
        ),
      ),
      title: const Text(titulo, textAlign: TextAlign.center),
      content: const Text(
        'Con tu permiso, TRAZA mostrará tu frecuencia cardiaca, calorías y '
        'pasos al terminar y en la foto que compartas. Sin él puedes entrenar '
        'igual, pero sin esos datos.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(continuarSin),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(aceptar),
        ),
      ],
    );
  }
}
