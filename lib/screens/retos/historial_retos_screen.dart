import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/reto_del_usuario.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_reto.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// Historial de retos del corredor: los que completó, por fechas (SCRUM-174),
/// y los que se le vencieron sin cumplir (SCRUM-173).
///
/// Va por chips y no en secciones seguidas: con muchos retos, llegar a lo
/// vencido obligaría a desplazarse por todo lo completado. Se abre en "En
/// curso" porque es lo único sobre lo que el corredor todavía puede actuar.
class HistorialRetosScreen extends ConsumerWidget {
  const HistorialRetosScreen({super.key});

  static Key claveChip(SeccionHistorialRetos seccion) =>
      Key('historial-${seccion.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mios = ref.watch(misRetosProvider);
    final seccion = ref.watch(seccionHistorialRetosProvider);
    final ahora = ref.read(relojProvider)();

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Mis retos', onAtras: context.pop),
              FilaChips(
                children: [
                  for (final opcion in SeccionHistorialRetos.values)
                    ChipFiltro(
                      key: claveChip(opcion),
                      texto: opcion.etiqueta,
                      activo: opcion == seccion,
                      onTap: () =>
                          ref
                                  .read(seccionHistorialRetosProvider.notifier)
                                  .state =
                              opcion,
                    ),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(misRetosProvider),
                  child: switch (mios) {
                    AsyncData(value: final retos) => _Seccion(
                      retos: seccion.filtrar(retos, ahora),
                      seccion: seccion,
                      ahora: ahora,
                    ),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar tus retos',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () => ref.invalidate(misRetosProvider),
                        child: const Text('Reintentar'),
                      ),
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.retos,
    required this.seccion,
    required this.ahora,
  });

  final List<RetoDelUsuario> retos;
  final SeccionHistorialRetos seccion;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    if (retos.isEmpty) {
      // Cada pestaña dice lo suyo: un mensaje común obligaría a mirar qué
      // chip está activo para saber de qué está hablando.
      return EstadoVacio(
        icono: seccion.iconoVacio,
        titulo: seccion.tituloVacio,
        detalle: seccion.detalleVacio,
      );
    }

    // SCRUM-174: los completados van agrupados por día. Los demás no: lo que
    // importa de ellos es el progreso, no cuándo se activaron.
    if (seccion != SeccionHistorialRetos.completados) {
      return ListView(
        padding: _relleno,
        children: [
          for (final reto in retos) _FilaReto(reto: reto, ahora: ahora),
        ],
      );
    }

    return ListView(
      padding: _relleno,
      children: [
        for (final grupo in _porFecha(retos, ahora)) ...[
          _Fecha(texto: grupo.key),
          for (final reto in grupo.value) _FilaReto(reto: reto, ahora: ahora),
        ],
      ],
    );
  }

  static const _relleno = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    0,
    AppSpacing.lg,
    AppSpacing.xl,
  );

  /// Agrupa por día de completado, del más reciente al más antiguo.
  static List<MapEntry<String, List<RetoDelUsuario>>> _porFecha(
    List<RetoDelUsuario> retos,
    DateTime ahora,
  ) {
    final ordenados = [...retos]
      ..sort(
        (a, b) => (b.fechaCompletado ?? b.fechaActivacion).compareTo(
          a.fechaCompletado ?? a.fechaActivacion,
        ),
      );

    final grupos = <String, List<RetoDelUsuario>>{};
    for (final reto in ordenados) {
      final dia = _cuando(reto.fechaCompletado ?? reto.fechaActivacion, ahora);
      grupos.putIfAbsent(dia, () => []).add(reto);
    }
    return grupos.entries.toList();
  }

  static const _meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  /// `Hoy`, `Ayer` o `14 sep`, con el mismo criterio que el historial de
  /// entrenamientos.
  static String _cuando(DateTime fecha, DateTime ahora) {
    final dia = fecha.toLocal();
    final hoy = ahora.toLocal();
    // Días de calendario, en UTC para que un cambio de horario no convierta
    // un día en 23 horas.
    final dias = DateTime.utc(
      hoy.year,
      hoy.month,
      hoy.day,
    ).difference(DateTime.utc(dia.year, dia.month, dia.day)).inDays;

    if (dias == 0) return 'Hoy';
    if (dias == 1) return 'Ayer';
    final texto = '${dia.day} ${_meses[dia.month - 1]}';
    return dia.year == hoy.year ? texto : '$texto ${dia.year}';
  }
}

class _Fecha extends StatelessWidget {
  const _Fecha({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.ink3,
        ),
      ),
    );
  }
}

/// Un reto del historial, con lo que el corredor llegó a hacer.
class _FilaReto extends StatelessWidget {
  const _FilaReto({required this.reto, required this.ahora});

  final RetoDelUsuario reto;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final vencido = reto.vencidoEn(ahora);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TrazaCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Marca(reto: reto, vencido: vencido),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    reto.reto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: vencido ? AppColors.ink2 : AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InsigniaReto(
                  texto:
                      '${reto.completado ? '+' : ''}'
                      '${reto.reto.xpOtorgada} XP',
                  fondo: reto.completado
                      ? AppColors.primaryTint
                      : AppColors.bgAlt,
                  color: reto.completado
                      ? AppColors.primaryDark
                      : AppColors.ink3,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // El progreso importa sobre todo en lo vencido: saber que quedó
            // en 12 de 15 km es distinto de no haber empezado.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: reto.progreso,
                minHeight: 6,
                backgroundColor: AppColors.bgAlt,
                valueColor: AlwaysStoppedAnimation(
                  reto.completado
                      ? AppColors.primary
                      : vencido
                      ? AppColors.ink3
                      : AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${TarjetaReto.textoKm(reto.progresoKm)} de '
              '${TarjetaReto.textoKm(reto.reto.metaKm)} km',
              style: const TextStyle(fontSize: 12, color: AppColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.reto, required this.vencido});

  final RetoDelUsuario reto;
  final bool vencido;

  @override
  Widget build(BuildContext context) {
    final (icono, fondo, color) = reto.completado
        ? (Icons.check, AppColors.accentTint, AppColors.accentInk)
        : vencido
        ? (Icons.close, AppColors.bgAlt, AppColors.ink3)
        : (
            Icons.directions_run,
            AppColors.secondaryTint,
            AppColors.secondaryDark,
          );

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icono, size: 18, color: color),
    );
  }
}
