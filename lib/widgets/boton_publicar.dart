import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Hueco al final de las listas del foro para que [BotonPublicar] no tape
/// la última tarjeta: el botón (56) más su margen (16) y aire. El mismo de
/// la gestión de retos.
const espacioBotonPublicar = 96.0;

/// El "+" flotante para publicar en el foro, abajo a la derecha. Lo usan el
/// foro del corredor y la moderación del administrador.
///
/// Las listas que quedan debajo dejan [espacioBotonPublicar] al final: así
/// se puede llegar a la última tarjeta sin que el botón la tape.
class BotonPublicar extends StatelessWidget {
  const BotonPublicar({required this.onPressed, super.key});

  final VoidCallback onPressed;

  static const tooltip = 'Nueva publicación';

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      tooltip: tooltip,
      child: const Icon(Icons.add, size: 26),
    );
  }
}
