import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/rutas.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/widgets/traza_toast.dart';
import '../../../core/widgets/traza_top_bar.dart';
import 'perfil_controller.dart';
import 'widgets/mis_objetivos_section.dart';

/// Pantalla de perfil (`screen-profile`).
///
/// Es el primer paso después del registro: el usuario configura sus objetivos
/// y desde aquí continúa hacia la pantalla de permisos.
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TrazaTopBar(titulo: 'Perfil'),
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
              child: const _BotonGuardar(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Guarda los objetivos y, si todo sale bien, sigue hacia permisos.
///
/// Queda deshabilitado mientras no haya ningún objetivo marcado, mientras algún
/// valor sea inválido o mientras el guardado esté en curso. En los tres casos
/// la pantalla ya explica el motivo (estado vacío o error bajo el campo).
class _BotonGuardar extends StatelessWidget {
  const _BotonGuardar();

  @override
  Widget build(BuildContext context) {
    final controlador = context.watch<PerfilController>();

    return FilledButton(
      onPressed: controlador.puedeGuardar ? () => _guardar(context) : null,
      child: controlador.guardando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Guardar y continuar'),
    );
  }

  Future<void> _guardar(BuildContext context) async {
    final error = await context.read<PerfilController>().guardarObjetivos();
    if (!context.mounted) return;

    mostrarToast(context, error ?? 'Objetivos guardados');
    if (error == null) {
      context.go(Rutas.permisos);
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
