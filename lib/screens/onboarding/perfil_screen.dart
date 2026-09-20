import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/boton_cerrar_sesion.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';
import '../../services/perfil_provider.dart';
import '../../models/perfil_state.dart';
import '../../widgets/mis_objetivos_section.dart';

/// Pantalla de perfil (`screen-profile`).
///
/// Es el primer paso después del registro: el usuario configura sus objetivos
/// y desde aquí continúa hacia la pantalla de permisos. Si ya los había
/// configurado antes, la pantalla llega con sus valores precargados.
///
/// Terminado el onboarding es además una sección fija de la barra inferior:
/// se entra a mirar o cambiar los objetivos y se vuelve a la portada.
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({this.enOnboarding = false, super.key});

  /// Si viene del registro, guardar sigue hacia Permisos. Si no, guardar es
  /// solo guardar y se vuelve a la portada.
  final bool enOnboarding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TrazaTopBar(titulo: 'Perfil', accion: BotonCerrarSesion()),
            Expanded(child: _Cuerpo(enOnboarding: enOnboarding)),
          ],
        ),
      ),
    );
  }
}

class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({required this.enOnboarding});

  final bool enOnboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carga = ref.watch(perfilProvider.select((estado) => estado.carga));

    return switch (carga) {
      EstadoCarga.cargando => const Center(child: CircularProgressIndicator()),
      EstadoCarga.error => const _ErrorDeCarga(),
      EstadoCarga.listo => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: const [
                _CabeceraPerfil(),
                SizedBox(height: AppSpacing.xl),
                MisObjetivosSection(),
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
            child: _BotonGuardar(enOnboarding: enOnboarding),
          ),
        ],
      ),
    };
  }
}

/// No se pudo leer lo que el usuario tenía guardado.
///
/// Se bloquea la edición a propósito: guardar reemplaza el conjunto completo de
/// objetivos, así que hacerlo sin saber qué había los borraría.
class _ErrorDeCarga extends ConsumerWidget {
  const _ErrorDeCarga();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgAlt,
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 26,
                color: AppColors.ink3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No pudimos cargar tus objetivos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Revisa tu conexión e inténtalo de nuevo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.ink2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () =>
                  ref.read(perfilProvider.notifier).cargarObjetivos(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Guarda los objetivos y, si todo sale bien, sigue hacia permisos (en el
/// onboarding) o vuelve a la portada.
///
/// Queda deshabilitado mientras no haya ningún objetivo marcado, mientras algún
/// valor sea inválido o mientras el guardado esté en curso. En los tres casos
/// la pantalla ya explica el motivo (estado vacío o error bajo el campo).
class _BotonGuardar extends ConsumerWidget {
  const _BotonGuardar({required this.enOnboarding});

  final bool enOnboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(perfilProvider);

    return FilledButton(
      onPressed: estado.puedeGuardar ? () => _guardar(context, ref) : null,
      child: estado.guardando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(enOnboarding ? 'Guardar y continuar' : 'Guardar cambios'),
    );
  }

  Future<void> _guardar(BuildContext context, WidgetRef ref) async {
    final error = await ref.read(perfilProvider.notifier).guardarObjetivos();
    if (!context.mounted) return;

    mostrarToast(context, error ?? 'Objetivos guardados');
    if (error == null) {
      context.go(enOnboarding ? '/permisos' : '/inicio');
    }
  }
}

/// Identidad del usuario: avatar con iniciales, nombre y correo.
class _CabeceraPerfil extends StatelessWidget {
  const _CabeceraPerfil();

  @override
  Widget build(BuildContext context) {
    final usuario = _usuarioActual();
    final correo = usuario?.email;
    final nombre = _nombreDe(usuario) ?? 'Tu perfil';

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.secondaryTint,
          ),
          child: Text(
            _iniciales(nombre, correo),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryDark,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombre,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                correo ?? 'Sin sesión iniciada',
                style: const TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// El usuario autenticado, o null si Supabase todavía no está inicializado
/// (por ejemplo en pruebas de widget) o no hay sesión.
User? _usuarioActual() {
  try {
    return Supabase.instance.client.auth.currentUser;
  } on Object {
    return null;
  }
}

String? _nombreDe(User? usuario) {
  final metadatos = usuario?.userMetadata;
  final nombre = metadatos?['full_name'] ?? metadatos?['name'];
  return nombre is String && nombre.trim().isNotEmpty ? nombre.trim() : null;
}

String _iniciales(String nombre, String? correo) {
  final palabras = nombre.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (palabras.length >= 2) {
    return (palabras[0][0] + palabras[1][0]).toUpperCase();
  }
  final base = correo ?? nombre;
  return base.isEmpty ? '?' : base[0].toUpperCase();
}
