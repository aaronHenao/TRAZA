import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/estado_permisos.dart';
import '../../services/auth_service.dart';
import '../../services/permisos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/tarjeta_permiso.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Pantalla de permisos (`screen-permissions`, SCRUM-76).
///
/// Llega después del perfil y explica para qué usa la app la ubicación y los
/// datos de salud. Ninguno es obligatorio: el usuario puede seguir sin
/// concederlos y se le vuelven a pedir cuando use una función que los necesite.
class PermisosScreen extends ConsumerStatefulWidget {
  const PermisosScreen({super.key});

  @override
  ConsumerState<PermisosScreen> createState() => _PermisosScreenState();
}

class _PermisosScreenState extends ConsumerState<PermisosScreen> {
  static const _mensajeAhoraNo = 'Podrás activarlo luego cuando lo necesites';

  /// Avisa cuando la app vuelve al frente, por ejemplo al regresar de los
  /// ajustes del teléfono, para mostrar el permiso como quedó allá.
  late final AppLifecycleListener _ciclo;

  /// Mientras se marca el onboarding en Supabase, para evitar un doble toque.
  bool _continuando = false;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(
      onResume: () => ref.read(permisosProvider.notifier).actualizar(),
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  /// SCRUM-81: último paso del onboarding. Queda marcado para que el próximo
  /// ingreso vaya directo a Inicio.
  Future<void> _continuar() async {
    setState(() => _continuando = true);
    await ref.read(authServiceProvider).completarOnboarding();
    if (!mounted) return;
    context.go('/inicio');
  }

  /// SCRUM-77: pide la ubicación y explica qué pasa según la respuesta.
  Future<void> _permitirUbicacion() async {
    final resultado = await ref
        .read(permisosProvider.notifier)
        .solicitarUbicacion();
    if (!mounted) return;

    switch (resultado) {
      case EstadoPermiso.concedido:
        // La tarjeta ya cambia sola a "Permiso concedido".
        break;
      case EstadoPermiso.denegado:
      case EstadoPermiso.desconocido:
      // geolocator no lo devuelve; si llegara, para el usuario es igual.
      case EstadoPermiso.noDisponible:
        mostrarToast(
          context,
          'Sin ubicación no podrás registrar tus recorridos',
          separacionInferior: 90,
        );
      case EstadoPermiso.bloqueado:
        await _explicarAjustes();
    }
  }

  /// SCRUM-78: abre Health Connect o Apple Health para elegir qué datos
  /// comparte. Negarlo no bloquea nada: el resumen sale sin esas métricas.
  Future<void> _permitirSalud() async {
    final resultado = await ref
        .read(permisosProvider.notifier)
        .solicitarSalud();
    if (!mounted) return;

    switch (resultado) {
      case EstadoPermiso.concedido:
        break;
      case EstadoPermiso.noDisponible:
        await _explicarSaludNoDisponible();
      case EstadoPermiso.denegado:
      case EstadoPermiso.bloqueado:
      case EstadoPermiso.desconocido:
        mostrarToast(
          context,
          'Tu resumen no mostrará métricas de salud',
          separacionInferior: 90,
        );
    }
  }

  /// En Android los datos llegan por Health Connect; si falta, se ofrece
  /// instalarlo. En web o escritorio no hay de dónde leerlos.
  Future<void> _explicarSaludNoDisponible() async {
    final esAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!esAndroid) {
      mostrarToast(
        context,
        'Este dispositivo no permite compartir datos de salud',
        separacionInferior: 90,
      );
      return;
    }

    final instalar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Falta Health Connect'),
        content: const Text(
          'TRAZA lee tus datos de salud a través de Health Connect, la app de '
          'Google que los reúne. Instálala y vuelve a intentarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Instalar'),
          ),
        ],
      ),
    );
    if (instalar == true) {
      await ref.read(permisosProvider.notifier).instalarProveedorSalud();
    }
  }

  /// El sistema ya no muestra su ventana: la única salida son los ajustes.
  Future<void> _explicarAjustes() async {
    final abrir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubicación desactivada'),
        content: const Text(
          'Para registrar tus recorridos, activa el permiso de ubicación en '
          'los ajustes del teléfono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
    if (abrir == true) {
      await ref.read(permisosProvider.notifier).abrirAjustes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final permisos = ref.watch(permisosProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const TrazaTopBar(titulo: 'Permisos'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                children: [
                  const Text(
                    'TRAZA necesita estos permisos para registrar tus '
                    'entrenamientos. Puedes concederlos ahora o más adelante.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.ink2,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TarjetaPermiso(
                    icono: Icons.location_on_outlined,
                    titulo: 'Ubicación',
                    descripcion:
                        'Necesaria para trazar tu recorrido y calcular la '
                        'distancia mientras entrenas.',
                    textoBoton: 'Permitir ubicación',
                    concedido: permisos.ubicacion == EstadoPermiso.concedido,
                    onPermitir: permisos.solicitandoUbicacion
                        ? null
                        : _permitirUbicacion,
                    onAhoraNo: () => mostrarToast(context, _mensajeAhoraNo),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TarjetaPermiso(
                    icono: Icons.favorite_outline,
                    titulo: 'Datos de salud',
                    descripcion:
                        'Con tu permiso, TRAZA registrará métricas de salud '
                        'durante tus entrenamientos y las mostrará en tu '
                        'resumen.',
                    textoBoton: 'Permitir acceso',
                    concedido: permisos.salud == EstadoPermiso.concedido,
                    onPermitir: permisos.solicitandoSalud
                        ? null
                        : _permitirSalud,
                    onAhoraNo: () => mostrarToast(context, _mensajeAhoraNo),
                  ),
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
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _continuando ? null : _continuar,
                  child: const Text('Continuar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
