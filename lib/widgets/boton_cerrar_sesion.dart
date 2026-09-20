import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import 'traza_top_bar.dart';

/// Botón circular para cerrar sesión. Pide confirmación, cierra la sesión de
/// Supabase y de Google, y vuelve al login.
class BotonCerrarSesion extends ConsumerWidget {
  const BotonCerrarSesion({super.key});

  Future<void> _cerrarSesion(BuildContext context, WidgetRef ref) async {
    // Confirmación: el botón está junto a otros y se puede tocar sin querer.
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Tendrás que volver a iniciar sesión para registrar tus '
          'entrenamientos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    await ref.read(authServiceProvider).cerrarSesion();
    if (!context.mounted) return;
    // go: sin sesión, atrás no debe volver a las pantallas de la app.
    context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrazaIconButton(
      icon: Icons.logout,
      tooltip: 'Cerrar sesión',
      onPressed: () => _cerrarSesion(context, ref),
    );
  }
}
