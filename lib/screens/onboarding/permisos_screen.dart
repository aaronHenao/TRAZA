import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/tarjeta_permiso.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Pantalla de permisos (`screen-permissions`, SCRUM-76).
///
/// Llega después del perfil y explica para qué usa la app la ubicación y los
/// datos de salud. Ninguno es obligatorio: el usuario puede seguir sin
/// concederlos y se le vuelven a pedir cuando use una función que los necesite.
class PermisosScreen extends StatelessWidget {
  const PermisosScreen({super.key});

  static const _mensajeAhoraNo = 'Podrás activarlo luego cuando lo necesites';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TrazaTopBar(titulo: 'Permisos'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                children: [
                  const Text(
                    'TRAZA necesita estos permisos para registrar tus '
                    'entrenamientos. Puedes concederlos ahora o más adelante.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink2,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TarjetaPermiso(
                    icono: Icons.location_on_outlined,
                    titulo: 'Ubicación',
                    descripcion:
                        'Necesaria para trazar tu recorrido y calcular la '
                        'distancia mientras entrenas.',
                    textoBoton: 'Permitir ubicación',
                    // Se conecta con el permiso real en SCRUM-77.
                    onPermitir: null,
                    onAhoraNo: () => mostrarToast(context, _mensajeAhoraNo),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TarjetaPermiso(
                    icono: Icons.favorite_outline,
                    titulo: 'Datos de salud',
                    descripcion:
                        'Con tu permiso, TRAZA registrará métricas de salud '
                        'durante tus entrenamientos y las mostrará en tu '
                        'resumen.',
                    textoBoton: 'Permitir acceso',
                    // Se conecta con el permiso real en SCRUM-78.
                    onPermitir: null,
                    onAhoraNo: () => mostrarToast(context, _mensajeAhoraNo),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/inicio'),
                  child: const Text('Continuar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
