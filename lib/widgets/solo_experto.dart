import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/rol_ganado.dart';
import '../services/roles_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Deja pasar a [hijo] solo si la cuenta desbloqueó el Runner Experto
/// (SCRUM-228).
///
/// El gemelo de `SoloAdministrador`, con una diferencia de fondo: el rol de
/// administrador se asigna a mano y el de experto se gana corriendo. Por eso
/// aquí, a quien todavía no lo tiene, no se le dice "no puedes" sino cuánto le
/// falta —eso lo muestra la pantalla de SCRUM-195—.
///
/// Es presentación, nada más: quien impide de verdad la acción es RLS, con
/// `es_experto()`. Ante un fallo al leer el rol se niega el paso, porque
/// dejar entrar a quien quizá no es experto solo llevaría a una acción que la
/// base va a rechazar.
class SoloExperto extends ConsumerWidget {
  const SoloExperto({required this.hijo, super.key});

  /// La pantalla exclusiva del rol que se protege.
  final Widget hijo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(esExpertoProvider)) {
      AsyncData(value: true) => hijo,
      AsyncData() => const _SinElRol(),
      AsyncError() => const _SinElRol(),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Lo que ve quien todavía no desbloqueó el rol.
class _SinElRol extends StatelessWidget {
  const _SinElRol();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgAlt,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 30,
                    color: AppColors.ink3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Esto es de ${RolGanable.experto.nombre}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Sigue sumando niveles y se desbloquea solo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  // `go`: no se vuelve a una pantalla en la que no se podía
                  // estar.
                  onPressed: () => context.go('/inicio'),
                  child: const Text('Volver al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
