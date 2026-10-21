import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/moderacion_foro.dart';
import '../../models/publicacion_foro.dart';
import '../../models/reporte_foro.dart';
import '../../services/foro_provider.dart';
import '../foro/detalle_publicacion_screen.dart';
import '../foro/nueva_publicacion_screen.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/boton_publicar.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_moderacion.dart';
import '../../widgets/tarjeta_publicacion.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Lo que el administrador ve del foro (SCRUM-323 y SCRUM-337).
///
/// "Publicadas" es lo que está a la vista. Las demás pestañas salen de
/// `moderaciones_foro` y traen publicaciones, comentarios y ediciones:
/// lo que la IA dejó pendiente (y el administrador decide), lo que todavía
/// analiza y lo rechazado, con quién lo rechazó, cuándo y por qué
/// (SCRUM-322).
///
/// Desde aquí el administrador también publica (SCRUM-354), y en
/// "Reportadas" ve lo que los corredores reportaron, sin saber quién
/// (SCRUM-369).
class ModeracionForoScreen extends ConsumerWidget {
  const ModeracionForoScreen({super.key});

  static const ruta = '/admin/foro';

  static const claveNueva = Key('moderacion-nueva-publicacion');
  static const claveMotivo = Key('moderacion-motivo');
  static const claveConfirmarRechazo = Key('moderacion-confirmar-rechazo');
  static Key claveReportada(String publicacionId) =>
      Key('moderacion-reportada-$publicacionId');

  static Key claveVista(VistaModeracionForo vista) =>
      Key('moderacion-${vista.name}');

  static const aprobada = 'Aprobada: ya se ve en el foro';
  static const rechazada = 'Rechazada: el autor verá el motivo';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SCRUM-357: lo nuevo, lo editado y los veredictos aparecen sin refrescar.
    ref.watch(foroEnVivoProvider);
    final publicaciones = ref.watch(moderacionForoProvider);
    final moderaciones = ref.watch(moderacionesAdminProvider);
    final reportadas = ref.watch(publicacionesReportadasProvider);
    final vista = ref.watch(vistaModeracionForoProvider);

    void recargar() {
      ref
        ..invalidate(moderacionForoProvider)
        ..invalidate(moderacionesAdminProvider)
        ..invalidate(reportesForoProvider);
    }

    Future<void> nueva() async {
      await context.push(NuevaPublicacionScreen.rutaAdmin);
      recargar();
    }

    int cuantas(VistaModeracionForo opcion) => switch (opcion) {
      VistaModeracionForo.publicadas => switch (publicaciones) {
        AsyncData(value: final lista) =>
          lista.where((p) => p.estado == EstadoPublicacion.publicada).length,
        _ => 0,
      },
      // Publicaciones distintas, no reportes: es lo que hay que revisar.
      VistaModeracionForo.reportadas => switch (reportadas) {
        AsyncData(value: final lista) => lista.length,
        _ => 0,
      },
      VistaModeracionForo(:final estado) => switch (moderaciones) {
        AsyncData(value: final lista) =>
          lista.where((m) => m.estado == estado).length,
        _ => 0,
      },
    };

    return Scaffold(
      // Como en el foro: abajo a la derecha, con hueco al final de las
      // listas para que no tape la última tarjeta ni sus botones.
      floatingActionButton: BotonPublicar(key: claveNueva, onPressed: nueva),
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Moderación del foro', onAtras: context.pop),
              FilaChips(
                children: [
                  for (final opcion in VistaModeracionForo.values)
                    ChipFiltro(
                      key: claveVista(opcion),
                      texto: '${opcion.etiqueta} (${cuantas(opcion)})',
                      activo: opcion == vista,
                      onTap: () =>
                          ref.read(vistaModeracionForoProvider.notifier).state =
                              opcion,
                    ),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (vista) {
                    VistaModeracionForo.publicadas => _Publicadas(
                      onRecargar: recargar,
                    ),
                    VistaModeracionForo.reportadas => _Reportadas(
                      onRecargar: recargar,
                    ),
                    _ => _Moderaciones(vista: vista, onRecargar: recargar),
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

class _Publicadas extends ConsumerWidget {
  const _Publicadas({required this.onRecargar});

  final VoidCallback onRecargar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtradas = ref.watch(moderacionForoFiltradaProvider);
    final ahora = ref.read(relojProvider)();

    return switch (filtradas) {
      AsyncData(value: final lista) when lista.isEmpty => const EstadoVacio(
        icono: Icons.forum_outlined,
        titulo: 'Nadie ha publicado todavía',
        detalle: 'Aquí verás lo que los corredores publiquen en el foro.',
      ),
      AsyncData(value: final lista) => _Lista(
        cuantos: lista.length,
        item: (context, i) => TarjetaPublicacion(
          key: TarjetaPublicacion.claveDe(lista[i].id),
          publicacion: lista[i],
          ahora: ahora,
          conEstado: true,
          onTap: () =>
              context.push(DetallePublicacionScreen.rutaAdminDe(lista[i].id)),
        ),
      ),
      AsyncError() => _ErrorDeCarga(onReintentar: onRecargar),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Moderaciones extends ConsumerWidget {
  const _Moderaciones({required this.vista, required this.onRecargar});

  final VistaModeracionForo vista;
  final VoidCallback onRecargar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtradas = ref.watch(moderacionesDeLaVistaProvider);
    // Las faltas se cuentan sobre toda la moderación, no solo la pestaña.
    final todas = ref.watch(moderacionesAdminProvider).valueOrNull ?? const [];

    return switch (filtradas) {
      AsyncData(value: final lista) when lista.isEmpty => switch (vista) {
        VistaModeracionForo.pendientes => const EstadoVacio(
          icono: Icons.task_alt_rounded,
          titulo: 'Nada pendiente',
          detalle:
              'Cuando la IA tenga dudas sobre algo, aparecerá aquí para que '
              'lo decidas.',
        ),
        VistaModeracionForo.enRevision => const EstadoVacio(
          icono: Icons.hourglass_empty_rounded,
          titulo: 'Nada en revisión',
          detalle:
              'Lo que se publica se analiza en segundos. Si algo se queda '
              'aquí, la IA no respondió: puedes decidirlo tú.',
        ),
        _ => const EstadoVacio(
          icono: Icons.shield_outlined,
          titulo: 'No hay nada rechazado',
          detalle:
              'Aquí verás lo que rechacen la IA o los administradores, con '
              'el motivo, quién lo decidió y cuándo.',
        ),
      },
      AsyncData(value: final lista) => _Lista(
        cuantos: lista.length,
        item: (context, i) {
          final m = lista[i];
          return TarjetaModeracion(
            moderacion: m,
            paraElAdmin: true,
            faltasDelAutor: faltasDe(m.autorId, todas),
            onAprobar: m.abierta ? () => _decidir(context, ref, m, true) : null,
            onRechazar: m.abierta
                ? () => _decidir(context, ref, m, false)
                : null,
            onTap: () => context.push(
              DetallePublicacionScreen.rutaAdminDe(m.publicacionId),
            ),
          );
        },
      ),
      AsyncError() => _ErrorDeCarga(onReintentar: onRecargar),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Lo que reportaron los corredores, una tarjeta por publicación
/// (SCRUM-369). Lo reportado más recientemente va primero.
class _Reportadas extends ConsumerWidget {
  const _Reportadas({required this.onRecargar});

  final VoidCallback onRecargar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportadas = ref.watch(publicacionesReportadasProvider);

    return switch (reportadas) {
      AsyncData(value: final lista) when lista.isEmpty => const EstadoVacio(
        icono: Icons.flag_outlined,
        titulo: 'Nada reportado',
        detalle:
            'Cuando un corredor reporte una publicación, aparecerá aquí con '
            'el motivo.',
      ),
      AsyncData(value: final lista) => _Lista(
        cuantos: lista.length,
        item: (context, i) => _TarjetaReportada(
          reportada: lista[i],
          onTap: () => context.push(
            DetallePublicacionScreen.rutaAdminDe(lista[i].publicacionId),
          ),
        ),
      ),
      AsyncError() => _ErrorDeCarga(onReintentar: onRecargar),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Una publicación reportada: cuántas veces y por qué. Nunca dice quién la
/// reportó (criterio 2 de SCRUM-369).
class _TarjetaReportada extends StatelessWidget {
  const _TarjetaReportada({required this.reportada, required this.onTap});

  final PublicacionReportada reportada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cuantos = reportada.cuantos;

    return TrazaCard(
      key: ModeracionForoScreen.claveReportada(reportada.publicacionId),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 16,
                color: AppColors.danger,
              ),
              const SizedBox(width: 6),
              Text(
                cuantos == 1 ? '1 reporte' : '$cuantos reportes',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reportada.titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Por ${reportada.autorNombre}',
            style: const TextStyle(fontSize: 12, color: AppColors.ink2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reportada.motivos.map((m) => m.etiqueta).join(' · '),
            style: const TextStyle(fontSize: 13, color: AppColors.ink),
          ),
          // Lo que contó cada corredor: con "Otro" es el motivo entero.
          for (final detalle in reportada.detalles) ...[
            const SizedBox(height: 4),
            Text(
              '“$detalle”',
              style: const TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppColors.ink2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Aprueba o rechaza [moderacion] (SCRUM-337). Rechazar pide el motivo, que
/// es lo que leerá el autor.
Future<void> _decidir(
  BuildContext context,
  WidgetRef ref,
  ModeracionForo moderacion,
  bool aprobar,
) async {
  String? motivo;
  if (!aprobar) {
    motivo = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoRechazo(moderacion: moderacion),
    );
    if (motivo == null) return;
  }

  final resultado = await ref
      .read(decisionModeracionProvider)
      .decidir(moderacion, aprobar: aprobar, motivo: motivo);
  if (!context.mounted) return;

  mostrarToast(context, switch (resultado) {
    ModeracionDecidida() =>
      aprobar ? ModeracionForoScreen.aprobada : ModeracionForoScreen.rechazada,
    DecisionSinMotivo() => DecisionModeracion.sinMotivo,
    DecisionYaResuelta() => DecisionModeracion.yaResuelta,
    DecisionNoGuardada(:final mensaje) => mensaje,
  });
}

/// Pide el motivo del rechazo. Viene lleno con lo que marcó la IA, si marcó
/// algo, para no reescribirlo.
class _DialogoRechazo extends StatefulWidget {
  const _DialogoRechazo({required this.moderacion});

  final ModeracionForo moderacion;

  @override
  State<_DialogoRechazo> createState() => _DialogoRechazoState();
}

class _DialogoRechazoState extends State<_DialogoRechazo> {
  late final _motivo = TextEditingController(
    text: widget.moderacion.categorias.join(', '),
  );
  String? _error;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _motivo.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = DecisionModeracion.sinMotivo);
      return;
    }
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rechazar ${widget.moderacion.queEs.toLowerCase()}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'El autor verá este motivo y contará como una falta.',
            style: TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: ModeracionForoScreen.claveMotivo,
            controller: _motivo,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              hintText: 'Ej.: Spam, lenguaje ofensivo…',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: ModeracionForoScreen.claveConfirmarRechazo,
          onPressed: _confirmar,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.cuantos, required this.item});

  final int cuantos;
  final IndexedWidgetBuilder item;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        espacioBotonPublicar,
      ),
      itemCount: cuantos,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: item,
    );
  }
}

class _ErrorDeCarga extends StatelessWidget {
  const _ErrorDeCarga({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      icono: Icons.cloud_off_outlined,
      titulo: 'No pudimos cargar el foro',
      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      accion: OutlinedButton(
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    );
  }
}
