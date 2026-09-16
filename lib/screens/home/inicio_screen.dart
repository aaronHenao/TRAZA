import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/boton_cerrar_sesion.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';
import '../../models/estado_permisos.dart';
import '../../services/actividad_provider.dart';
import '../../services/entrenamiento_provider.dart';
import '../../services/permisos_provider.dart';
import '../../widgets/requiere_permiso_ubicacion.dart';
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

  /// Un toque y la actividad arranca: se comprueban los permisos (SCRUM-97),
  /// se crea el entrenamiento (SCRUM-99) y se abre la pantalla del
  /// entrenamiento en curso, sin pasos intermedios.
  Future<void> _iniciar() async {
    if (_iniciando) return;
    setState(() => _iniciando = true);
    try {
      // Antes de crear nada: sin ubicación no hay recorrido que registrar, y
      // un entrenamiento que nadie va a usar quedaría abierto en la base.
      if (!await _hayPermisoDeUbicacion()) return;

      final error = await ref.read(inicioEntrenamientoProvider).iniciar();
      if (!mounted) return;

      // Sin entrenamiento creado la actividad no arranca: se explica por qué
      // y el botón queda libre para volver a intentarlo (SCRUM-100).
      if (error != null) {
        _avisar(error);
        return;
      }

      // Fija la actividad: mientras el entrenamiento dure no se puede
      // cambiar (SCRUM-94).
      ref.read(actividadIniciadaProvider.notifier).marcarIniciada();
      // `push` y no `go`: al descartar se vuelve a esta pantalla. Se espera a
      // esa vuelta, así el botón sigue ocupado mientras dura la actividad y
      // dos toques seguidos no pueden crear dos entrenamientos.
      await context.push('/tracking');
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  /// El permiso de ubicación es obligatorio (SCRUM-97): si falta se pide en
  /// el momento, para que conceder no sea un paso más del flujo.
  ///
  /// El de datos de salud no se toca aquí: es opcional y lo ofrece la propia
  /// pantalla de entrenamiento (SCRUM-83) antes de empezar.
  Future<bool> _hayPermisoDeUbicacion() async {
    final permisos = ref.read(permisosProvider.notifier);
    // Si todavía no se le preguntó al sistema, `desconocido` no significa que
    // falte: se consulta antes de mostrarle nada al usuario.
    if (!ref.read(permisosProvider).consultado) await permisos.actualizar();

    var ubicacion = ref.read(permisosProvider).ubicacion;

    // Bloqueado no: ahí el sistema ya no muestra su ventana y pedirlo otra
    // vez no haría nada.
    if (ubicacion != EstadoPermiso.concedido &&
        ubicacion != EstadoPermiso.bloqueado) {
      ubicacion = await permisos.solicitarUbicacion();
    }
    if (ubicacion == EstadoPermiso.concedido) return true;
    if (!mounted) return false;

    _avisar(RequierePermisoUbicacion.mensaje);
    // Si está bloqueado solo se puede reactivar desde los ajustes, y a ellos
    // se llega desde la pantalla de permisos.
    if (ubicacion == EstadoPermiso.bloqueado) context.push('/permisos');
    return false;
  }

  /// Por encima de "Iniciar actividad", para que se pueda volver a tocar
  /// mientras el aviso sigue visible.
  void _avisar(String mensaje) =>
      mostrarToast(context, mensaje, separacionInferior: 90);

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
