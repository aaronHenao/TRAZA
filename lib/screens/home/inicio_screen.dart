import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/boton_cerrar_sesion.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';
import '../../services/actividad_provider.dart';
import '../../services/entrenamiento_provider.dart';
import '../../widgets/chips_tipo_actividad.dart';
import '../../widgets/seccion_iniciar_entrenamiento.dart';

/// Pantalla de inicio (`screen-home` del prototipo): el usuario elige su
/// actividad y arranca el entrenamiento.
///
/// La estructura es de SCRUM-91, los chips con la actividad elegida de
/// SCRUM-92, la configuración de inicio de SCRUM-93, el bloqueo de la
/// actividad durante el entrenamiento de SCRUM-94 y el inicio con un solo
/// toque de SCRUM-96.
class InicioScreen extends ConsumerStatefulWidget {
  const InicioScreen({super.key});

  @override
  ConsumerState<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends ConsumerState<InicioScreen> {
  /// El entrenamiento se está creando. Es estado de la pantalla, no del
  /// dominio: solo sirve para que el botón espere y un segundo toque no cree
  /// otro entrenamiento (SCRUM-96).
  bool _iniciando = false;

  /// Un toque y la actividad arranca: se crea el entrenamiento (SCRUM-99) y
  /// se abre la pantalla del entrenamiento en curso, sin pasos intermedios.
  Future<void> _iniciar() async {
    if (_iniciando) return;
    setState(() => _iniciando = true);

    final error = await ref.read(inicioEntrenamientoProvider).iniciar();
    if (!mounted) return;
    setState(() => _iniciando = false);

    // Sin entrenamiento creado la actividad no arranca: se explica por qué y
    // el botón queda libre para volver a intentarlo (SCRUM-100).
    if (error != null) {
      mostrarToast(context, error);
      return;
    }

    // Fija la actividad: mientras el entrenamiento dure no se puede cambiar
    // (SCRUM-94).
    ref.read(actividadIniciadaProvider.notifier).marcarIniciada();
    // `push` y no `go`: al descartar la actividad se vuelve a esta pantalla.
    context.push('/tracking');
  }

  @override
  Widget build(BuildContext context) {
    final actividad = ref.watch(actividadSeleccionadaProvider);
    final configuracion = ref.watch(configuracionInicioProvider);
    final iniciada = ref.watch(actividadIniciadaProvider);

    final String? aviso;
    if (iniciada) {
      aviso = 'Hay un entrenamiento en curso: no puedes cambiar la actividad.';
    } else if (actividad != null && configuracion == null) {
      // Hay actividad elegida, pero viene del catálogo local porque no hay
      // sesión: sin id no se puede crear el entrenamiento (ver
      // ConfiguracionInicio.para).
      aviso = 'Inicia sesión para empezar a entrenar.';
    } else {
      aviso = null;
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          // `.home-wrap` del prototipo.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Cabecera(),
              const SizedBox(height: 24),
              const ChipsTipoActividad(),
              const SizedBox(height: 24),
              Expanded(
                child: SeccionIniciarEntrenamiento(
                  actividad: actividad?.nombre,
                  // Sin configuración no hay entrenamiento posible: el aviso
                  // ya explica que hay que iniciar sesión.
                  onIniciar: configuracion == null ? null : _iniciar,
                  aviso: aviso,
                  iniciando: _iniciando,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saludo y accesos al historial, los permisos y cerrar sesión (`.home-head`
/// del prototipo).
class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Listo para entrenar',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.19,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Elige tu actividad y comienza',
                style: TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
            ],
          ),
        ),
        // Historial de entrenamientos (SCRUM-125). push: "atrás" vuelve a
        // Inicio.
        TrazaIconButton(
          icon: Icons.schedule,
          onPressed: () => context.push('/historial'),
          tooltip: 'Historial',
        ),
        const SizedBox(width: 8),
        // Revisar y conceder permisos después del onboarding (SCRUM-85).
        // push: "atrás" vuelve a Inicio.
        TrazaIconButton(
          icon: Icons.shield_outlined,
          onPressed: () => context.push('/permisos'),
          tooltip: 'Permisos',
        ),
        const SizedBox(width: 8),
        const BotonCerrarSesion(),
      ],
    );
  }
}
