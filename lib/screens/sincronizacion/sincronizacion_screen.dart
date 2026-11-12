import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/estado_envio_recorrido.dart';
import '../../models/recorrido_local.dart';
import '../../services/almacen_recorrido.dart';
import '../../services/reloj_provider.dart';
import '../../services/sincronizacion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/fecha_relativa.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Lo que quedó en el teléfono sin subir a Supabase (Desarrollo Móvil,
/// sección 8 de los lineamientos).
///
/// Separa el estado del negocio del de la sincronización: el entrenamiento ya
/// está guardado, y lo que puede faltar es subir los puntos de su recorrido.
/// Desde aquí el corredor reintenta lo pendiente y descarta lo que la base
/// rechazó, que reintentar no arregla.
class SincronizacionScreen extends ConsumerStatefulWidget {
  const SincronizacionScreen({super.key});

  static const ruta = '/sincronizacion';
  static const titulo = 'Sincronización';

  static const claveLista = Key('sincronizacion-lista');
  static const claveReintentar = Key('sincronizacion-reintentar');
  static const claveReintentarLectura = Key(
    'sincronizacion-reintentar-lectura',
  );
  static Key claveFila(String id) => Key('sincronizacion-$id');
  static Key claveDescartar(String id) => Key('sincronizacion-descartar-$id');

  static const explicacion =
      'Tus entrenamientos ya quedaron guardados. Lo que falta es subir los '
      'puntos de su recorrido: se suben solos cuando hay conexión.';
  static const todoSubido = 'Todo está subido';
  static const sinLectura = 'No pudimos leer lo guardado en el teléfono';

  /// El estado del negocio, que no cambia mientras se sincroniza.
  static const entrenamientoGuardado = 'Entrenamiento guardado';

  static String puntos(int cuantos) =>
      cuantos == 1 ? '1 punto sin subir' : '$cuantos puntos sin subir';

  @override
  ConsumerState<SincronizacionScreen> createState() =>
      _SincronizacionScreenState();
}

class _SincronizacionScreenState extends ConsumerState<SincronizacionScreen> {
  /// Mientras se reintenta, para no lanzar dos subidas a la vez.
  bool _reintentando = false;

  Future<void> _reintentar() async {
    setState(() => _reintentando = true);
    try {
      final subidos = await ref
          .read(sincronizacionRecorridosProvider)
          .reintentar();
      if (!mounted) return;
      mostrarToast(
        context,
        subidos > 0
            ? SincronizacionRecorridos.subidos(subidos)
            : SincronizacionRecorridos.sinSubir,
      );
    } finally {
      if (mounted) setState(() => _reintentando = false);
    }
  }

  Future<void> _descartar(RecorridoLocal recorrido) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmarDescarte(recorrido: recorrido),
    );
    if (confirmado != true || !mounted) return;

    final hecho = await ref
        .read(sincronizacionRecorridosProvider)
        .descartar(recorrido.entrenamientoId);
    if (!mounted) return;
    mostrarToast(
      context,
      hecho
          ? SincronizacionRecorridos.descartado
          : SincronizacionRecorridos.noSeDescarto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorridos = ref.watch(recorridosPorSubirProvider);
    final ahora = ref.read(relojProvider)();

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: SincronizacionScreen.titulo,
                onAtras: context.pop,
              ),
              Expanded(
                child: switch (recorridos) {
                  AsyncData(:final value) when value.isEmpty =>
                    const EstadoVacio(
                      icono: Icons.cloud_done_outlined,
                      titulo: SincronizacionScreen.todoSubido,
                      detalle:
                          'Tus recorridos ya están en la nube. Si alguno se '
                          'queda sin subir, aparece aquí.',
                    ),
                  AsyncData(:final value) => _Lista(
                    recorridos: value,
                    ahora: ahora,
                    reintentando: _reintentando,
                    onReintentar: _reintentar,
                    onDescartar: _descartar,
                  ),
                  AsyncError() => EstadoVacio(
                    icono: Icons.error_outline_rounded,
                    titulo: SincronizacionScreen.sinLectura,
                    detalle: 'Inténtalo de nuevo.',
                    accion: OutlinedButton(
                      key: SincronizacionScreen.claveReintentarLectura,
                      onPressed: () =>
                          ref.invalidate(recorridosLocalesProvider),
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

/// La explicación, un recorrido por fila y, si algo se puede reintentar, el
/// botón para hacerlo.
class _Lista extends StatelessWidget {
  const _Lista({
    required this.recorridos,
    required this.ahora,
    required this.reintentando,
    required this.onReintentar,
    required this.onDescartar,
  });

  final List<RecorridoLocal> recorridos;
  final DateTime ahora;
  final bool reintentando;
  final VoidCallback onReintentar;
  final ValueChanged<RecorridoLocal> onDescartar;

  @override
  Widget build(BuildContext context) {
    final hayReintentables = recorridos.any(
      (recorrido) => EstadoEnvioRecorrido.de(recorrido).reintentable,
    );

    return ListView(
      key: SincronizacionScreen.claveLista,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        const Text(
          SincronizacionScreen.explicacion,
          style: TextStyle(fontSize: 13, color: AppColors.ink2, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final recorrido in recorridos) ...[
          _Fila(
            recorrido: recorrido,
            ahora: ahora,
            onDescartar: () => onDescartar(recorrido),
          ),
          const Divider(height: 1, color: AppColors.line),
        ],
        if (hayReintentables) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            key: SincronizacionScreen.claveReintentar,
            onPressed: reintentando ? null : onReintentar,
            icon: reintentando
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(reintentando ? 'Subiendo…' : 'Reintentar ahora'),
          ),
        ],
      ],
    );
  }
}

/// Un recorrido: que el entrenamiento está guardado, en qué va su subida,
/// por qué falló si falló, y Descartar si la base lo rechazó.
class _Fila extends StatelessWidget {
  const _Fila({
    required this.recorrido,
    required this.ahora,
    required this.onDescartar,
  });

  final RecorridoLocal recorrido;
  final DateTime ahora;
  final VoidCallback onDescartar;

  @override
  Widget build(BuildContext context) {
    final estado = EstadoEnvioRecorrido.de(recorrido);
    final (icono, fondo, color) = switch (estado) {
      EstadoEnvioRecorrido.rechazado => (
        Icons.block_rounded,
        AppColors.dangerTint,
        AppColors.danger,
      ),
      EstadoEnvioRecorrido.fallido => (
        Icons.cloud_off_rounded,
        AppColors.accentTint,
        AppColors.accentInk,
      ),
      _ => (
        Icons.cloud_upload_outlined,
        AppColors.secondaryTint,
        AppColors.secondaryDark,
      ),
    };
    final motivo = recorrido.ultimoError;
    final detalle = [
      estado.etiqueta,
      if (recorrido.puntosSinEnviar > 0)
        SincronizacionScreen.puntos(recorrido.puntosSinEnviar),
    ].join(' · ');

    return Padding(
      key: SincronizacionScreen.claveFila(recorrido.entrenamientoId),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: fondo, shape: BoxShape.circle),
            child: Icon(icono, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        SincronizacionScreen.entrenamientoGuardado,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fechaRelativa(recorrido.actualizadoEn, ahora),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (motivo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    motivo,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink2,
                      height: 1.45,
                    ),
                  ),
                ],
                if (estado == EstadoEnvioRecorrido.rechazado)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: SincronizacionScreen.claveDescartar(
                        recorrido.entrenamientoId,
                      ),
                      onPressed: onDescartar,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Descartar'),
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

/// Qué se pierde al descartar: los puntos que no subieron, sin vuelta atrás.
class _ConfirmarDescarte extends StatelessWidget {
  const _ConfirmarDescarte({required this.recorrido});

  final RecorridoLocal recorrido;

  @override
  Widget build(BuildContext context) {
    final cuantos = recorrido.puntosSinEnviar;
    final puntos = cuantos == 1 ? 'el punto' : 'los $cuantos puntos';

    return AlertDialog(
      title: const Text('Descartar recorrido'),
      content: Text(
        'Se borran del teléfono $puntos que la base no aceptó. Reintentar no '
        'lo arregla: el entrenamiento ya no existe o es de otra cuenta. Esto '
        'no se puede deshacer.',
        style: const TextStyle(
          fontSize: 13.5,
          color: AppColors.ink2,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Descartar'),
        ),
      ],
    );
  }
}
