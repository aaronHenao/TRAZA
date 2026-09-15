import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/resumen_entrenamiento.dart';
import '../../services/entrenamiento_provider.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/traza_theme.dart';
import '../../widgets/seccion_salud.dart';
import '../../widgets/traza_top_bar.dart';

/// Resumen del entrenamiento recién finalizado (`screen-summary`, SCRUM-117).
///
/// Muestra el tiempo, la distancia, el ritmo promedio y el recorrido de la
/// sesión. El id del entrenamiento llega en la ruta (SCRUM-122) y los datos,
/// del cierre de la actividad (SCRUM-121) o, si no llegaron, de Supabase
/// (SCRUM-118).
class ResumenScreen extends ConsumerWidget {
  const ResumenScreen({
    required this.entrenamientoId,
    required this.resumen,
    super.key,
  });

  /// Arma la pantalla con los argumentos de la navegación: el id del
  /// entrenamiento en la ruta (`/resumen/<id>`) y los datos de la sesión en
  /// `extra`.
  factory ResumenScreen.desdeRuta(GoRouterState estado) {
    final extra = estado.extra;
    return ResumenScreen(
      entrenamientoId: estado.pathParameters['entrenamientoId'],
      resumen: extra is ResumenEntrenamiento ? extra : null,
    );
  }

  /// Ruta del resumen de [entrenamientoId]: `/resumen/<id>`, o `/resumen` a
  /// secas si se entrenó sin sesión y no hay id.
  static String rutaPara(String? entrenamientoId) => entrenamientoId == null
      ? '/resumen'
      : '/resumen/${Uri.encodeComponent(entrenamientoId)}';

  /// Entrenamiento que pide la navegación, o null si no hay sesión.
  final String? entrenamientoId;

  /// Datos de la sesión que acaba de terminar, tal como los dejó el cierre.
  final ResumenEntrenamiento? resumen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Igual que en el prototipo (`closeSummary`), cerrar lleva al inicio.
    void volverAlInicio() => context.go('/inicio');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TrazaTopBar(
              titulo: 'Resumen',
              accion: TrazaIconButton(
                icon: Icons.close,
                onPressed: volverAlInicio,
                tooltip: 'Cerrar',
              ),
            ),
            Expanded(child: _cuerpo(ref, volverAlInicio)),
          ],
        ),
      ),
    );
  }

  /// Qué mostrar: solo el resumen del entrenamiento que indica la ruta
  /// (SCRUM-122), nunca "el último" de una lista.
  Widget _cuerpo(WidgetRef ref, VoidCallback volverAlInicio) {
    // Recién terminada la actividad, los datos llegan con la navegación y no
    // hace falta consultar nada.
    final datos = resumen;
    if (datos != null && datos.correspondeA(entrenamientoId)) {
      return _ContenidoResumen(resumen: datos, onVolver: volverAlInicio);
    }

    // Sin esos datos (se recargó la página, se abrió la ruta a mano o son de
    // otra sesión) se lee de Supabase el entrenamiento de la ruta, solo si
    // está finalizado (SCRUM-118). Sin sesión no hay id que buscar.
    final id = entrenamientoId;
    if (id == null) return _SinResumen(onVolver: volverAlInicio);

    return ref
        .watch(entrenamientoFinalizadoProvider(id))
        .when(
          // Al reintentar también se ve el indicador de carga.
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ErrorAlCargar(
            onReintentar: () =>
                ref.invalidate(entrenamientoFinalizadoProvider(id)),
          ),
          data: (guardado) => guardado == null
              ? _SinResumen(onVolver: volverAlInicio)
              : _ContenidoResumen(resumen: guardado, onVolver: volverAlInicio),
        );
  }
}

/// El resumen de la sesión, como en `screen-summary`.
class _ContenidoResumen extends ConsumerWidget {
  const _ContenidoResumen({required this.resumen, required this.onVolver});

  final ResumenEntrenamiento resumen;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Cabecera(subtitulo: resumen.subtitulo(ref.read(relojProvider)())),
        Padding(
          // `.summary-body`: 20 px y 18 px entre bloques.
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Metrica(valor: resumen.tiempo, etiqueta: 'Tiempo'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Metrica(
                      valor: resumen.distancia,
                      etiqueta: 'Distancia',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Ritmo(valor: resumen.ritmo),
              // Solo aparece si hay permiso y datos (SCRUM-79).
              SeccionSalud.deResumen(resumen),
              const SizedBox(height: 18),
              const _Recorrido(),
              const SizedBox(height: 18),
              // El entrenamiento ya quedó guardado al tocar "Finalizar"
              // (SCRUM-121), así que este botón solo cierra el resumen.
              FilledButton(
                onPressed: onVolver,
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `.summary-hero`: check en círculo, título y actividad con la fecha.
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.subtitulo});

  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryTint,
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 26),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 30,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            '¡Entrenamiento completado!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.19,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
        ],
      ),
    );
  }
}

/// `.stat-box`: un valor grande con su etiqueta debajo.
class _Metrica extends StatelessWidget {
  const _Metrica({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        children: [
          // Un entrenamiento de más de 99 horas no debe desbordar la caja.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.summary-pace`: "Ritmo promedio" con el valor en negrita.
class _Ritmo extends StatelessWidget {
  const _Ritmo({required this.valor});

  final String valor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'Ritmo promedio: ',
        children: [
          TextSpan(
            text: valor,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
    );
  }
}

/// `.summary-map`: el recuadro oscuro del recorrido, con el mismo degradado
/// que la pantalla del entrenamiento en curso.
///
/// SCRUM-120 dibuja aquí el trayecto con `ResumenEntrenamiento.puntos`; hasta
/// entonces se muestra el recuadro vacío.
class _Recorrido extends StatelessWidget {
  const _Recorrido();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: 160,
        decoration: const BoxDecoration(gradient: trazaTrackingGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_rounded,
                size: 26,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 6),
              Text(
                'Recorrido no disponible',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No hay un entrenamiento finalizado que mostrar.
class _SinResumen extends StatelessWidget {
  const _SinResumen({required this.onVolver});

  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return _EstadoCentrado(
      icono: Icons.insights_outlined,
      titulo: 'No hay un entrenamiento para mostrar',
      detalle: 'El resumen aparece al finalizar una actividad.',
      accion: OutlinedButton(
        onPressed: onVolver,
        child: const Text('Volver al inicio'),
      ),
    );
  }
}

/// No se pudo leer el entrenamiento de Supabase, igual que el error de carga
/// del perfil.
class _ErrorAlCargar extends StatelessWidget {
  const _ErrorAlCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return _EstadoCentrado(
      icono: Icons.cloud_off_outlined,
      titulo: 'No pudimos cargar el resumen',
      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      accion: OutlinedButton(
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    );
  }
}

/// Icono en círculo gris, título, detalle y una acción, centrados.
class _EstadoCentrado extends StatelessWidget {
  const _EstadoCentrado({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget accion;

  @override
  Widget build(BuildContext context) {
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
              child: Icon(icono, size: 26, color: AppColors.ink3),
            ),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.ink2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            accion,
          ],
        ),
      ),
    );
  }
}
