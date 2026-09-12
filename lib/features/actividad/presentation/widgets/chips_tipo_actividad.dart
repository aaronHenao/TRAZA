import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../domain/tipo_actividad.dart';
import '../actividad_providers.dart';

/// Fila de chips para elegir el tipo de actividad (`.activity-chip-row` del
/// prototipo). Solo puede haber uno marcado a la vez, y con un entrenamiento
/// en curso no se pueden tocar (SCRUM-94).
class ChipsTipoActividad extends ConsumerWidget {
  const ChipsTipoActividad({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(tiposActividadProvider);
    final seleccionada = ref.watch(actividadSeleccionadaProvider);
    final iniciada = ref.watch(actividadIniciadaProvider);

    return switch (catalogo) {
      AsyncData() when catalogo.requireValue.isEmpty => const _Aviso(
        'No hay actividades disponibles.',
      ),
      AsyncData() => Row(
        children: [
          for (final (indice, tipo) in catalogo.requireValue.indexed) ...[
            if (indice > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Chip(
                tipo: tipo,
                seleccionado: tipo == seleccionada,
                onTap: iniciada
                    ? null
                    : () => ref
                          .read(actividadSeleccionadaProvider.notifier)
                          .seleccionar(tipo),
              ),
            ),
          ],
        ],
      ),
      AsyncError() => _ErrorDeCarga(
        onReintentar: () => ref.invalidate(tiposActividadProvider),
      ),
      _ => const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    };
  }
}

/// Un chip (`.activity-chip`); marcado usa el estilo `.activity-chip.on`.
///
/// Sin [onTap] queda deshabilitado. El marcado conserva su color para que se
/// vea con qué actividad se está entrenando.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.tipo,
    required this.seleccionado,
    required this.onTap,
  });

  final TipoActividad tipo;
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;

    return Semantics(
      button: true,
      enabled: habilitado,
      selected: seleccionado,
      child: Material(
        color: seleccionado ? AppColors.primary : AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
            child: Text(
              tipo.nombre,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: seleccionado
                    ? Colors.white
                    : habilitado
                    ? AppColors.ink2
                    : AppColors.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.mensaje);

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Center(
        child: Text(
          mensaje,
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
      ),
    );
  }
}

class _ErrorDeCarga extends StatelessWidget {
  const _ErrorDeCarga({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'No pudimos cargar las actividades.',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
          ),
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
