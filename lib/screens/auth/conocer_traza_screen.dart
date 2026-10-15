import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/presentacion_traza.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// Qué es TRAZA y qué se puede hacer en ella (SCRUM-279).
///
/// Solo muestra: el texto es el de `PresentacionTraza` (SCRUM-278), y de
/// quién la abre y a dónde vuelve se encarga SCRUM-280.
///
/// Es informativa, así que no ofrece ningún atajo para registrarse ni entrar:
/// no reemplaza esas pantallas, y quien llegue desde el login tiene que poder
/// volver a ellas sin haber hecho nada por el camino.
class ConocerTrazaScreen extends StatelessWidget {
  const ConocerTrazaScreen({super.key});

  static const titulo = 'Conoce TRAZA';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: titulo,
                // Se vuelve a donde se entró. Si se abrió de frente, no hay a
                // dónde volver.
                onAtras: context.canPop() ? context.pop : null,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  children: [
                    const _Portada(),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      PresentacionTraza.queEs,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.ink2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _Rotulo('LO QUE PUEDES HACER'),
                    const SizedBox(height: AppSpacing.md),
                    for (final funcion in FuncionTraza.values) ...[
                      TarjetaFuncion(funcion: funcion),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      PresentacionTraza.invitacion,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La identidad de la marca: el logo y el lema sobre el degradado del
/// prototipo.
class _Portada extends StatelessWidget {
  const _Portada();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
      ),
      child: const Column(
        children: [
          // El logo es morado sobre transparente; encima del degradado se
          // perdería, así que se tiñe de blanco sin tocar el archivo.
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
            child: MarcaTraza(),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            PresentacionTraza.lema,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una de las funciones de la app, con su icono.
///
/// El icono vive aquí y no en [FuncionTraza] porque es decisión de la
/// interfaz: el modelo guarda lo que se dice, no cómo se dibuja.
class TarjetaFuncion extends StatelessWidget {
  const TarjetaFuncion({required this.funcion, super.key});

  final FuncionTraza funcion;

  static const _iconos = {
    FuncionTraza.registrar: Icons.play_circle_outline,
    FuncionTraza.retos: Icons.flag_outlined,
    FuncionTraza.niveles: Icons.stairs_outlined,
    FuncionTraza.insignias: Icons.workspace_premium_outlined,
    FuncionTraza.rutas: Icons.map_outlined,
  };

  /// El icono de [funcion]. Si alguna vez se añade una función sin icono, se
  /// dibuja uno genérico en vez de dejar el hueco.
  IconData get icono => _iconos[funcion] ?? Icons.circle_outlined;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, size: 21, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  funcion.titulo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  funcion.detalle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.66,
        color: AppColors.ink2,
      ),
    );
  }
}
