import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_permisos.dart';
import '../services/permisos_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Antes de [child], ofrece el permiso de datos de salud si falta (SCRUM-83).
///
/// A diferencia de la ubicación, no es obligatorio: si el usuario lo niega o
/// elige seguir sin él, [child] se abre igual y el entrenamiento queda sin
/// datos de salud.
class OfrecePermisoSalud extends ConsumerWidget {
  const OfrecePermisoSalud({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = ref.watch(permisosProvider);

    if (!permisos.consultado) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ofrecer = switch (permisos.salud) {
      EstadoPermiso.concedido || EstadoPermiso.noDisponible => false,
      // iOS nunca dice si se negó: queda en desconocido y se ofrece. Si ya se
      // había preguntado, iOS responde al instante sin mostrar nada.
      EstadoPermiso.denegado ||
      EstadoPermiso.bloqueado ||
      EstadoPermiso.desconocido => !permisos.saludOmitida,
    };
    if (!ofrecer) return child;

    return Scaffold(
      body: SafeArea(
        child: _Oferta(
          solicitando: permisos.solicitandoSalud,
          onPermitir: () => _permitir(ref),
          onOmitir: () => ref.read(permisosProvider.notifier).omitirSalud(),
        ),
      ),
    );
  }

  Future<void> _permitir(WidgetRef ref) async {
    final permisos = ref.read(permisosProvider.notifier);
    final resultado = await permisos.solicitarSalud();
    // Si no lo concedió, se entrena igual sin datos de salud.
    if (resultado != EstadoPermiso.concedido) permisos.omitirSalud();
  }
}

class _Oferta extends StatelessWidget {
  const _Oferta({
    required this.solicitando,
    required this.onPermitir,
    required this.onOmitir,
  });

  final bool solicitando;
  final VoidCallback onPermitir;
  final VoidCallback onOmitir;

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
                    Icons.favorite_outline,
                    size: 32,
                    color: AppColors.secondaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  '¿Registrar tus datos de salud?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Con tu permiso, TRAZA mostrará tu frecuencia cardiaca, '
                  'calorías y pasos al terminar el entrenamiento. Sin él '
                  'puedes entrenar igual, pero sin esos datos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.ink2,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: solicitando ? null : onPermitir,
            child: const Text('Permitir'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: solicitando ? null : onOmitir,
            child: const Text('Continuar sin datos de salud'),
          ),
        ],
      ),
    );
  }
}
