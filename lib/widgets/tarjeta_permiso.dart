import 'package:flutter/material.dart';

import '../models/estado_permisos.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// Tarjeta que explica un permiso, muestra en qué estado está y deja
/// concederlo (`.permission-card` del prototipo, SCRUM-76 y SCRUM-85).
///
/// Concedido se pinta en el color primario y el botón se cambia por la
/// etiqueta "Permiso concedido".
class TarjetaPermiso extends StatelessWidget {
  const TarjetaPermiso({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.estado,
    required this.textoBoton,
    required this.onPermitir,
    this.onAhoraNo,
    super.key,
  });

  final IconData icono;
  final String titulo;

  /// Para qué funciones de la app se necesita el permiso.
  final String descripcion;
  final EstadoPermiso estado;
  final String textoBoton;

  /// Si es null, el botón no se muestra (por ejemplo, salud en web).
  final VoidCallback? onPermitir;

  /// Solo en el onboarding. Si es null, no se muestra "Ahora no".
  final VoidCallback? onAhoraNo;

  bool get _concedido => estado == EstadoPermiso.concedido;

  @override
  Widget build(BuildContext context) {
    final onPermitir = this.onPermitir;
    final onAhoraNo = this.onAhoraNo;

    return TrazaCard(
      seleccionada: _concedido,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _concedido
                      ? AppColors.primary
                      : AppColors.secondaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icono,
                  size: 20,
                  color: _concedido ? Colors.white : AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descripcion,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink2,
                        height: 1.5,
                      ),
                    ),
                    _EstadoSinConceder(estado: estado),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Wrap y no Row: con letra grande o pantalla angosta, "Ahora no"
          // baja de línea en lugar de desbordarse.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (_concedido)
                const _EtiquetaConcedido()
              else if (onPermitir != null)
                OutlinedButton(
                  onPressed: onPermitir,
                  // `.btn-sm`: más bajo que el botón normal del tema.
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(textoBoton),
                ),
              if (!_concedido && onAhoraNo != null)
                TextButton(
                  onPressed: onAhoraNo,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ink3,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Ahora no'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Línea con el estado cuando el permiso no está concedido (SCRUM-85).
class _EstadoSinConceder extends StatelessWidget {
  const _EstadoSinConceder({required this.estado});

  final EstadoPermiso estado;

  @override
  Widget build(BuildContext context) {
    final (icono, texto, color) = switch (estado) {
      EstadoPermiso.denegado => (
        Icons.remove_circle_outline,
        'No concedido',
        AppColors.ink2,
      ),
      EstadoPermiso.bloqueado => (
        Icons.block,
        'Bloqueado: actívalo en los ajustes del teléfono',
        AppColors.danger,
      ),
      EstadoPermiso.noDisponible => (
        Icons.info_outline,
        'No disponible en este dispositivo',
        AppColors.ink2,
      ),
      // Concedido tiene su etiqueta abajo; desconocido no dice nada útil.
      EstadoPermiso.concedido || EstadoPermiso.desconocido => (null, '', null),
    };
    if (icono == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaConcedido extends StatelessWidget {
  const _EtiquetaConcedido();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 16, color: AppColors.primaryDark),
        SizedBox(width: 6),
        Text(
          'Permiso concedido',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
      ],
    );
  }
}
