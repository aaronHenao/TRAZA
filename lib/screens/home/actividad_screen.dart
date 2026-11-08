import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/ruta.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';
import '../../models/estado_permisos.dart';
import '../../services/actividad_provider.dart';
import '../../services/entrenamiento_provider.dart';
import '../../services/permisos_provider.dart';
import '../../widgets/requiere_permiso_ubicacion.dart';
import '../../widgets/chips_tipo_actividad.dart';
import '../../widgets/seccion_iniciar_entrenamiento.dart';
import '../../widgets/tarjeta_ruta_explorar.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/ventana_permiso_salud.dart';
import '../onboarding/perfil_screen.dart';

/// Pantalla para elegir la actividad y arrancar el entrenamiento
/// (`screen-home` del prototipo del sprint 1). Se llega desde el botón "+"
/// de la portada.
///
/// La estructura es de SCRUM-91, los chips con la actividad elegida de
/// SCRUM-92, la configuración de inicio de SCRUM-93, el bloqueo de la
/// actividad durante el entrenamiento de SCRUM-94 y el inicio con un solo
/// toque de SCRUM-96.
class ActividadScreen extends ConsumerStatefulWidget {
  const ActividadScreen({super.key, this.ruta});

  /// La ruta oficial que se va a correr, si se llegó desde "Correr esta
  /// ruta" en su detalle (rutas oficiales, etapa 3). Null en un
  /// entrenamiento libre.
  final Ruta? ruta;

  static const claveRutaElegida = Key('actividad-ruta-elegida');

  /// Arma la pantalla con la navegación: desde "Correr esta ruta" llega la
  /// ruta en `extra`; desde el "+" de la portada, nada. Cualquier otra cosa
  /// en `extra` se ignora y abre un entrenamiento libre.
  factory ActividadScreen.desdeRuta(GoRouterState estado) {
    final extra = estado.extra;
    return ActividadScreen(ruta: extra is Ruta ? extra : null);
  }

  @override
  ConsumerState<ActividadScreen> createState() => _ActividadScreenState();
}

class _ActividadScreenState extends ConsumerState<ActividadScreen> {
  /// El entrenamiento se está creando. Es estado de la pantalla, no del
  /// dominio: solo sirve para que el botón espere y un segundo toque no cree
  /// otro entrenamiento (SCRUM-96).
  bool _iniciando = false;

  /// Un toque y la actividad arranca: se comprueban los permisos (SCRUM-97 y
  /// SCRUM-131), se crea el entrenamiento (SCRUM-99) y se abre la pantalla del
  /// entrenamiento en curso.
  Future<void> _iniciar() async {
    if (_iniciando) return;
    setState(() => _iniciando = true);
    try {
      // Antes de crear nada: sin ubicación no hay recorrido que registrar, y
      // un entrenamiento que nadie va a usar quedaría abierto en la base.
      if (!await _hayPermisoDeUbicacion()) return;
      if (!mounted) return;

      // La salud es opcional: si falta se ofrece cada vez, y lo conceda o no,
      // la actividad arranca. Solo cerrar la ventana la deja sin empezar.
      if (!await ofrecerPermisoSalud(context, ref)) return;
      if (!mounted) return;

      final error = await ref
          .read(inicioEntrenamientoProvider)
          .iniciar(ruta: widget.ruta);
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
              if (widget.ruta case final ruta?) ...[
                const SizedBox(height: AppSpacing.md),
                _RutaElegida(ruta: ruta),
              ],
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

/// La ruta oficial que se va a correr (rutas oficiales, etapa 3), para que
/// el corredor sepa que este entrenamiento cuenta para su mapa.
class _RutaElegida extends StatelessWidget {
  const _RutaElegida({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      key: ActividadScreen.claveRutaElegida,
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vas a correr',
                  style: TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
                Text(
                  ruta.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  TarjetaRutaExplorar.distanciaYDificultad(ruta),
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Saludo, vuelta a la portada y accesos al historial y a los permisos
/// (`.home-head` del prototipo).
class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Se llega con el "+" de la portada, así que hay a dónde volver sin
        // arrancar nada. Cerrar sesión ya no está aquí: vive en Perfil, que
        // ahora tiene su sección en la barra inferior.
        TrazaIconButton(
          icon: Icons.chevron_left,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/inicio'),
          tooltip: 'Volver',
        ),
        const SizedBox(width: 8),
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
        // Historial de entrenamientos (SCRUM-125). Desde SCRUM-285 está en el
        // perfil, que es una sección de la barra: se va con `go`, y de ahí se
        // vuelve por la barra.
        TrazaIconButton(
          icon: Icons.schedule,
          onPressed: () =>
              context.go(PerfilScreen.rutaCon(PestanaPerfil.actividades)),
          tooltip: 'Historial',
        ),
        const SizedBox(width: 8),
        // Revisar y conceder permisos después del onboarding (SCRUM-85).
        // push: "atrás" vuelve a esta pantalla.
        TrazaIconButton(
          icon: Icons.shield_outlined,
          onPressed: () => context.push('/permisos'),
          tooltip: 'Permisos',
        ),
      ],
    );
  }
}
