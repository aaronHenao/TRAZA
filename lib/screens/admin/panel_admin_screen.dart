import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/boton_cerrar_sesion.dart';
import '../../widgets/traza_card.dart';
import 'gestion_niveles_screen.dart';
import 'gestion_retos_screen.dart';

/// Panel del administrador (SCRUM-194): a donde llega al entrar.
///
/// Es una pantalla de navegación, sin lógica propia: deja claro que la sesión
/// es de administrador y ofrece un acceso por cada área que puede administrar.
/// Cada área nueva se suma como una tarjeta más.
class PanelAdminScreen extends StatelessWidget {
  const PanelAdminScreen({super.key});

  static const claveRetos = Key('panel-admin-retos');
  static const claveNiveles = Key('panel-admin-niveles');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              const _Cabecera(),
              const SizedBox(height: 24),
              _TarjetaAcceso(
                clave: claveRetos,
                icono: Icons.flag_outlined,
                titulo: 'Gestionar retos',
                detalle: 'Crea y revisa los retos que ven los corredores.',
                // `push`: desde la gestión se vuelve aquí.
                onTap: () => context.push(GestionRetosScreen.ruta),
              ),
              const SizedBox(height: AppSpacing.md),
              _TarjetaAcceso(
                clave: claveNiveles,
                icono: Icons.stairs_outlined,
                titulo: 'Gestionar niveles',
                detalle:
                    'Define la progresión y la experiencia que pide cada '
                    'nivel.',
                onTap: () => context.push(GestionNivelesScreen.ruta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Panel de administrador',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.19,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Lo que configuras aquí es lo que ven los corredores',
                style: TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
              SizedBox(height: AppSpacing.sm),
              EtiquetaRol(),
            ],
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        // El administrador no tiene pantalla de perfil, así que la salida vive
        // aquí, en la pantalla a la que siempre vuelve.
        BotonCerrarSesion(mensaje: BotonCerrarSesion.mensajeAdministrador),
      ],
    );
  }
}

/// Distintivo de que la sesión abierta es la del administrador.
///
/// Vive solo en el panel: repetirlo dentro de cada gestión sería recordar lo
/// mismo en todas las pantallas.
class EtiquetaRol extends StatelessWidget {
  const EtiquetaRol({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.secondaryTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 13, color: AppColors.secondaryDark),
          SizedBox(width: 5),
          Text(
            'Administrador',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acceso a un área administrable.
class _TarjetaAcceso extends StatelessWidget {
  const _TarjetaAcceso({
    required this.clave,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  final Key clave;
  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      key: clave,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, size: 22, color: AppColors.primaryDark),
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
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
        ],
      ),
    );
  }
}
