import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../domain/tipo_objetivo.dart';
import '../perfil_controller.dart';
import 'configuracion_valor_objetivo.dart';
import 'objetivo_card.dart';

/// Sección "Mis Objetivos" de la pantalla de perfil.
///
/// Permite marcar uno o varios objetivos deportivos y muestra un estado vacío
/// mientras no haya ninguno seleccionado.
class MisObjetivosSection extends StatelessWidget {
  const MisObjetivosSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controlador = context.watch<PerfilController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'MIS OBJETIVOS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink2,
            letterSpacing: 0.52,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Elige uno o varios objetivos para personalizar tu experiencia. '
          'Podrás modificarlos cuando quieras.',
          style: TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.6),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final tipo in TipoObjetivo.values) ...[
          ObjetivoCard(
            key: ValueKey(tipo),
            tipo: tipo,
            seleccionada: controlador.estaSeleccionado(tipo),
            onTap: () => controlador.alternar(tipo),
            // La fila de frecuencia se conecta en SCRUM-88.
            configuracion: tipo == TipoObjetivo.distancia
                ? ConfiguracionValorObjetivo(tipo: tipo)
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (controlador.sinObjetivos) const _EstadoVacio(),
      ],
    );
  }
}

/// Estado vacío: ningún objetivo seleccionado todavía.
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bg,
            ),
            child: const Icon(
              Icons.flag_outlined,
              size: 26,
              color: AppColors.ink3,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Aún no has elegido objetivos',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Selecciona al menos uno para personalizar tu experiencia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.ink2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
