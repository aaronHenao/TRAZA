import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/estado_permisos.dart';
import '../services/permisos_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Muestra [child] solo si hay permiso de ubicación (SCRUM-82).
///
/// Si no lo hay, en su lugar explica por qué hace falta y ofrece "Aceptar"
/// para pedirlo. Así [child] (por ejemplo, el entrenamiento en curso) nunca
/// arranca el GPS sin permiso.
class RequierePermisoUbicacion extends ConsumerStatefulWidget {
  const RequierePermisoUbicacion({required this.child, super.key});

  final Widget child;

  static const mensaje =
      'Para poder iniciar un recorrido, debe aceptar el permiso de ubicación';

  @override
  ConsumerState<RequierePermisoUbicacion> createState() =>
      _RequierePermisoUbicacionState();
}

class _RequierePermisoUbicacionState
    extends ConsumerState<RequierePermisoUbicacion> {
  /// Al volver de los ajustes del teléfono se consulta otra vez: si lo
  /// activó allá, [child] aparece solo.
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(
      onResume: () => ref.read(permisosProvider.notifier).actualizar(),
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  Future<void> _aceptar() async {
    final permisos = ref.read(permisosProvider.notifier);
    // Bloqueado: el sistema ya no muestra su ventana, solo queda ir a ajustes.
    if (ref.read(permisosProvider).ubicacion == EstadoPermiso.bloqueado) {
      await permisos.abrirAjustes();
      return;
    }
    await permisos.solicitarUbicacion();
  }

  void _volver() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/inicio');
    }
  }

  @override
  Widget build(BuildContext context) {
    final permisos = ref.watch(permisosProvider);

    if (permisos.ubicacion == EstadoPermiso.concedido) return widget.child;

    return Scaffold(
      body: SafeArea(
        child: !permisos.consultado
            ? const Center(child: CircularProgressIndicator())
            : _Aviso(
                bloqueado: permisos.ubicacion == EstadoPermiso.bloqueado,
                solicitando: permisos.solicitandoUbicacion,
                onAceptar: _aceptar,
                onVolver: _volver,
              ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.bloqueado,
    required this.solicitando,
    required this.onAceptar,
    required this.onVolver,
  });

  final bool bloqueado;
  final bool solicitando;
  final VoidCallback onAceptar;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.secondaryTint,
                  ),
                  child: const Icon(
                    Icons.location_off_outlined,
                    size: 32,
                    color: AppColors.secondaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  RequierePermisoUbicacion.mensaje,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  bloqueado
                      ? 'Lo desactivaste antes. Actívalo en los ajustes del '
                            'teléfono y vuelve a la app.'
                      : 'TRAZA la usa para trazar tu recorrido y calcular la '
                            'distancia mientras entrenas.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.ink2,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: solicitando ? null : onAceptar,
            child: const Text('Aceptar'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onVolver, child: const Text('Volver')),
        ],
      ),
    );
  }
}
