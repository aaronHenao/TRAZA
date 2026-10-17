import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/notificacion.dart';
import '../../services/notificaciones_provider.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/fecha_relativa.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/traza_top_bar.dart';

/// Los avisos del usuario (SCRUM-241, SCRUM-242).
///
/// Es donde encuentra lo que pasó mientras no estaba: que su ruta se publicó,
/// o que el administrador le retiró una publicación y por qué. El texto viene
/// escrito de la base, que es la que sabe de qué ruta o de qué motivo habla.
class NotificacionesScreen extends ConsumerStatefulWidget {
  const NotificacionesScreen({super.key});

  static const ruta = '/notificaciones';

  static const claveLista = Key('notificaciones-lista');
  static const claveReintentar = Key('notificaciones-reintentar');

  @override
  ConsumerState<NotificacionesScreen> createState() =>
      _NotificacionesScreenState();
}

class _NotificacionesScreenState extends ConsumerState<NotificacionesScreen> {
  /// Si ya se dieron por vistas en esta visita.
  bool _vistas = false;

  /// Abrir la bandeja es haberlas visto: apaga el contador de la campana.
  ///
  /// La lista en pantalla no se recarga, así que las que estaban sin leer
  /// siguen marcadas hasta que el usuario salga. Eso es lo que le deja ver
  /// qué era nuevo.
  ///
  /// Si la bandeja no cargó no hay nada que dar por visto.
  void _darPorVistas() {
    if (_vistas) return;
    _vistas = true;
    unawaited(ref.read(bandejaNotificacionesProvider).marcarVistas());
  }

  @override
  Widget build(BuildContext context) {
    // Con la bandeja abierta, lo que llegue entra solo. Recargar la lista
    // apaga de paso el resaltado de lo que estaba sin leer, que es el precio
    // de enseñar lo que hay ahora mismo.
    ref.watch(notificacionesEnVivoProvider);

    ref.listen(misNotificacionesProvider, (_, siguiente) {
      if (siguiente is AsyncData) _darPorVistas();
    });

    final notificaciones = ref.watch(misNotificacionesProvider);
    final ahora = ref.read(relojProvider)();

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Notificaciones', onAtras: context.pop),
              Expanded(
                child: switch (notificaciones) {
                  AsyncData(:final value) when value.isEmpty =>
                    const EstadoVacio(
                      icono: Icons.notifications_none_rounded,
                      titulo: 'No tienes notificaciones',
                      detalle:
                          'Aquí te avisamos cuando se publique una de tus '
                          'rutas o cuando haya novedades con lo que '
                          'compartes.',
                    ),
                  AsyncData(:final value) => RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(misNotificacionesProvider),
                    child: ListView.separated(
                      key: NotificacionesScreen.claveLista,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      itemCount: value.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.line),
                      itemBuilder: (_, i) =>
                          _Fila(notificacion: value[i], ahora: ahora),
                    ),
                  ),
                  AsyncError() => EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    titulo: 'No pudimos cargar tus notificaciones',
                    detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                    accion: OutlinedButton(
                      key: NotificacionesScreen.claveReintentar,
                      onPressed: () =>
                          ref.invalidate(misNotificacionesProvider),
                      child: const Text('Reintentar'),
                    ),
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un aviso: de qué es, qué dice y cuándo llegó.
class _Fila extends StatelessWidget {
  const _Fila({required this.notificacion, required this.ahora});

  final Notificacion notificacion;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final sinLeer = !notificacion.leida;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: sinLeer ? AppColors.secondaryTint : AppColors.bgAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(
              notificacion.tipo.icono,
              size: 18,
              color: sinLeer ? AppColors.secondaryDark : AppColors.ink3,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notificacion.titulo,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: sinLeer
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fechaRelativa(notificacion.fechaCreacion, ahora),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notificacion.mensaje,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink2,
                    height: 1.45,
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
