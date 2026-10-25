import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/boton_cerrar_sesion.dart';
import '../../widgets/traza_card.dart';
import '../home/runner_experto_screen.dart';
import '../rutas/rutas_por_clasificar_screen.dart';
import '../../services/roles_service.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';
import '../../services/perfil_provider.dart';
import '../../models/perfil_state.dart';
import '../../widgets/lista_historial.dart';
import '../../widgets/mis_objetivos_section.dart';
import '../../widgets/pestanas_segmentadas.dart';
import '../../widgets/seccion_insignias.dart';

/// Las dos caras del perfil (SCRUM-285).
enum PestanaPerfil {
  perfil(etiqueta: 'Perfil', parametro: 'perfil'),
  actividades(etiqueta: 'Actividades', parametro: 'actividades');

  const PestanaPerfil({required this.etiqueta, required this.parametro});

  final String etiqueta;

  /// Con qué valor de `?pestana=` la abre otra pantalla.
  final String parametro;

  /// La pestaña que pide la dirección. La del perfil si no pide ninguna o si
  /// pide una que no existe: entrar al perfil nunca debe fallar por eso.
  static PestanaPerfil desdeParametro(String? valor) =>
      PestanaPerfil.values.firstWhere(
        (pestana) => pestana.parametro == valor,
        orElse: () => PestanaPerfil.perfil,
      );
}

/// Pantalla de perfil (`screen-profile`).
///
/// Es el primer paso después del registro: el usuario configura sus objetivos
/// y desde aquí continúa hacia la pantalla de permisos. Si ya los había
/// configurado antes, la pantalla llega con sus valores precargados.
///
/// Terminado el onboarding es además una sección fija de la barra inferior,
/// con dos pestañas (SCRUM-285): lo suyo —objetivos, insignias y el rol— y
/// "Actividades", sus entrenamientos anteriores, que hasta esta historia
/// tenían sección propia en la barra.
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({
    this.enOnboarding = false,
    this.pestanaInicial = PestanaPerfil.perfil,
    super.key,
  });

  /// Si viene del registro, guardar sigue hacia Permisos. Si no, guardar es
  /// solo guardar y se vuelve a la portada.
  final bool enOnboarding;

  /// Con qué pestaña se abre. Quien venga a mirar los entrenamientos —el "Ver
  /// todos" de la portada, el reloj de Seleccionar actividad— entra directo a
  /// "Actividades".
  final PestanaPerfil pestanaInicial;

  static const ruta = '/perfil';

  static const claveRunnerExperto = Key('perfil-runner-experto');
  static const claveRutasPorClasificar = Key('perfil-rutas-por-clasificar');

  static Key clavePestana(PestanaPerfil pestana) =>
      Key('perfil-pestana-${pestana.name}');

  /// La dirección del perfil abierto en [pestana].
  static String rutaCon(PestanaPerfil pestana) =>
      pestana == PestanaPerfil.perfil
      ? ruta
      : '$ruta?pestana=${pestana.parametro}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TrazaTopBar(titulo: 'Perfil', accion: BotonCerrarSesion()),
            Expanded(
              child: _Cuerpo(
                enOnboarding: enOnboarding,
                pestanaInicial: pestanaInicial,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reparte la pantalla entre las pestañas y recuerda cuál está abierta.
class _Cuerpo extends StatefulWidget {
  const _Cuerpo({required this.enOnboarding, required this.pestanaInicial});

  final bool enOnboarding;
  final PestanaPerfil pestanaInicial;

  @override
  State<_Cuerpo> createState() => _CuerpoState();
}

class _CuerpoState extends State<_Cuerpo> {
  late var _pestana = widget.pestanaInicial;

  @override
  void didUpdateWidget(covariant _Cuerpo anterior) {
    super.didUpdateWidget(anterior);
    // Volver al perfil pidiendo otra pestaña la abre aunque la pantalla
    // siguiera montada, que es lo que pasa al llegar desde la barra inferior.
    if (widget.pestanaInicial != anterior.pestanaInicial) {
      _pestana = widget.pestanaInicial;
    }
  }

  @override
  Widget build(BuildContext context) {
    // En el onboarding el perfil es un paso del registro: sin pestañas, que
    // todavía no hay entrenamientos ni nada que mirar.
    if (widget.enOnboarding) return const _Objetivos(enOnboarding: true);

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: _CabeceraPerfil(),
        ),
        PestanasSegmentadas(
          children: [
            for (final pestana in PestanaPerfil.values)
              PestanaSegmentada(
                key: PerfilScreen.clavePestana(pestana),
                texto: pestana.etiqueta,
                abierta: pestana == _pestana,
                onTap: () => setState(() => _pestana = pestana),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: switch (_pestana) {
            PestanaPerfil.perfil => const _Objetivos(enOnboarding: false),
            // Los entrenamientos anteriores (SCRUM-44), que dejaron de ser una
            // sección de la barra para vivir aquí.
            PestanaPerfil.actividades => const ListaHistorial(),
          },
        ),
      ],
    );
  }
}

/// La pestaña del perfil: objetivos, insignias y el rol, con su botón de
/// guardar. Es también todo el cuerpo durante el onboarding.
class _Objetivos extends ConsumerWidget {
  const _Objetivos({required this.enOnboarding});

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
              children: [
                // Fuera del onboarding la cabecera va arriba, encima de las
                // pestañas: identifica al usuario en las dos.
                if (enOnboarding) const _CabeceraPerfil(),
                // Recién registrado todavía no hay nada que alcanzar: primero
                // termina el onboarding.
                if (!enOnboarding) const _InvitacionRunnerExperto(),
                // La bandeja del Runner Experto (SCRUM-363), solo para quien
                // tiene el rol.
                if (!enOnboarding) const _AccesoRutasPorClasificar(),
                const SizedBox(height: AppSpacing.xl),
                const MisObjetivosSection(),
                // Los logros del corredor (SCRUM-222), debajo de los
                // objetivos, que son lo que guarda el botón. En el onboarding
                // todavía no hay XP: ni se muestran ni se consultan.
                if (!enOnboarding) ...const [
                  SizedBox(height: AppSpacing.xl),
                  SeccionInsignias(),
                ],
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

/// La entrada a los requisitos y ventajas de Runner Experto (SCRUM-212).
class _InvitacionRunnerExperto extends StatelessWidget {
  const _InvitacionRunnerExperto();

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      key: PerfilScreen.claveRunnerExperto,
      // `push`: al cerrarla se vuelve al perfil.
      onTap: () => context.push(RunnerExpertoScreen.ruta),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.accentTint,
            child: Icon(
              Icons.workspace_premium_rounded,
              size: 22,
              color: AppColors.accentInk,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Quieres ser Runner Experto?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Mira qué necesitas y qué ganas.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.ink3),
        ],
      ),
    );
  }
}

/// Lo que el Runner Experto tiene por clasificar (SCRUM-363). A quien no tiene
/// el rol no se le muestra nada: para él ya está la invitación de arriba.
class _AccesoRutasPorClasificar extends ConsumerWidget {
  const _AccesoRutasPorClasificar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(esExpertoProvider).valueOrNull != true) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: TrazaCard(
        key: PerfilScreen.claveRutasPorClasificar,
        // `push`: al cerrarla se vuelve al perfil.
        onTap: () => context.push(RutasPorClasificarScreen.ruta),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.secondaryTint,
              child: Icon(
                Icons.terrain_outlined,
                size: 22,
                color: AppColors.secondaryDark,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rutas por clasificar',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Asígnales la dificultad antes de que se publiquen.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.ink3),
          ],
        ),
      ),
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
  final palabras = nombre
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (palabras.length >= 2) {
    return (palabras[0][0] + palabras[1][0]).toUpperCase();
  }
  final base = correo ?? nombre;
  return base.isEmpty ? '?' : base[0].toUpperCase();
}
