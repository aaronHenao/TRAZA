import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/rol_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Deja pasar a [hijo] solo si la sesión abierta es de administrador
/// (SCRUM-183).
///
/// Envuelve las rutas de administración para que escribir la dirección a mano
/// no sirva de atajo. Es presentación, nada más: quien impide de verdad que un
/// corredor escriba en `niveles` es RLS, con la policy de insert que exige
/// `es_admin()`. Por eso, ante un fallo al leer el rol, aquí se niega el paso
/// —al revés que en `PuertaAdmin`, donde lo seguro es dejar entrar como
/// corredor—: mostrar la gestión a quien quizá no es administrador solo
/// llevaría a un guardado que la base va a rechazar.
class SoloAdministrador extends ConsumerWidget {
  const SoloAdministrador({required this.hijo, super.key});

  /// La pantalla de administración que se protege.
  final Widget hijo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(esAdministradorProvider)) {
      AsyncData(value: true) => hijo,
      AsyncData() => const _SinAcceso(),
      AsyncError() => const _SinAcceso(),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Lo que ve quien no administra: por qué no entra y cómo salir de ahí.
class _SinAcceso extends StatelessWidget {
  const _SinAcceso();

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
                const Text(
                  'Esta sección es solo para administradores',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Tu cuenta entrena, no configura la progresión.',
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
