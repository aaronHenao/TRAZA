import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rol_ganado.dart';
import '../services/roles_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Lo que el rol le habilita al corredor, tal como se le cuenta al
/// desbloquearlo (criterio 2 de SCRUM-224).
///
/// Está vacía a propósito: cuáles son las funcionalidades exclusivas lo define
/// SCRUM-210, y escribir aquí unas inventadas sería prometerle al usuario algo
/// que la app no hace. Mientras tanto la ventana anuncia el rol sin listar
/// nada. Cuando esa subtarea aterrice, se llena esta lista y la ventana las
/// muestra sola.
const beneficiosRunnerExperto = <String>[];

/// Avisa al corredor de un rol que acaba de desbloquear y lo deja marcado
/// (SCRUM-229).
///
/// Se muestra una sola vez: al cerrarla se escribe `anunciado_en`, y la
/// función de la base solo lo escribe si estaba vacío. Si el aviso no se
/// pudiera marcar —sin red, por ejemplo—, volvería a salir la próxima vez, que
/// es preferible a que el corredor nunca se entere.
Future<void> anunciarRolDesbloqueado(
  BuildContext context,
  WidgetRef ref,
) async {
  final RolGanado? pendiente;
  try {
    pendiente = await ref.read(rolPorAnunciarProvider.future);
  } catch (error) {
    // El aviso es un extra: si los roles no se pueden leer, el corredor entra
    // a su portada igual y se le avisará la próxima vez.
    debugPrint('No se pudieron consultar los roles: $error');
    return;
  }
  if (pendiente == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => VentanaRolExperto(rol: pendiente!.rol),
  );

  try {
    await ref.read(rolesRepositoryProvider).marcarAnunciado(pendiente.rol);
    ref.invalidate(rolesGanadosProvider);
  } catch (error) {
    // Sin marcar, el aviso volverá a salir. Preferible a tragárselo y que el
    // corredor nunca se entere de que lo desbloqueó.
    debugPrint('No se pudo marcar el rol como anunciado: $error');
  }
}

/// La ventana que anuncia el rol desbloqueado.
class VentanaRolExperto extends StatelessWidget {
  const VentanaRolExperto({required this.rol, super.key});

  final RolGanable rol;

  static const claveCerrar = Key('rol-experto-entendido');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bg,
      title: Row(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('¡Desbloqueaste ${rol.nombre}!')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tus kilómetros te subieron de categoría. Ya tienes acceso a lo '
            'que el rol habilita.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppColors.ink2,
              height: 1.4,
            ),
          ),
          if (beneficiosRunnerExperto.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final beneficio in beneficiosRunnerExperto)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        beneficio,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: claveCerrar,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

/// Muestra el anuncio al entrar a la app, encima de [hijo] (criterio 2 de
/// SCRUM-224: "cuando ingresa a la aplicación").
///
/// Va envolviendo la portada y no dentro de ella para no mezclar el aviso con
/// lo que la portada muestra, y para que el administrador —que no entra por
/// ahí— no lo consulte nunca.
class AvisoRolNuevo extends ConsumerStatefulWidget {
  const AvisoRolNuevo({required this.hijo, super.key});

  final Widget hijo;

  @override
  ConsumerState<AvisoRolNuevo> createState() => _AvisoRolNuevoState();
}

class _AvisoRolNuevoState extends ConsumerState<AvisoRolNuevo> {
  @override
  void initState() {
    super.initState();
    // Después del primer frame: hasta que la portada no está montada no hay
    // dónde abrir la ventana.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) anunciarRolDesbloqueado(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.hijo;
}
