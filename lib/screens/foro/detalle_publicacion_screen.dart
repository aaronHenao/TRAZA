import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/comentario_foro.dart';
import '../../models/publicacion_foro.dart';
import '../../services/foro_provider.dart';
import '../../services/foro_service.dart';
import '../../services/reloj_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../utils/fecha_relativa.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_publicacion.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Una publicación del foro con sus comentarios y la caja para comentarla
/// (SCRUM-351).
///
/// El administrador la abre en [vistaModeracion]: ve la publicación en
/// cualquier estado, con su motivo, y comenta como cualquiera mientras esté
/// publicada. Lo que escribe el administrador lleva la insignia
/// "Administrador", y los comentarios del creador de la publicación, la de
/// "Autor" (SCRUM-354).
class DetallePublicacionScreen extends ConsumerWidget {
  const DetallePublicacionScreen({
    required this.publicacionId,
    this.vistaModeracion = false,
    super.key,
  });

  final String publicacionId;
  final bool vistaModeracion;

  static String rutaDe(String id) => '/foro/$id';
  static String rutaAdminDe(String id) => '/admin/foro/$id';

  /// Dónde se edita (SCRUM-355): debajo del detalle, en el foro o en la
  /// moderación según desde dónde se abrió.
  String get _rutaEditar =>
      '${vistaModeracion ? rutaAdminDe(publicacionId) : rutaDe(publicacionId)}'
      '/editar';

  static const claveCaja = Key('comentario-caja');
  static const claveEnviar = Key('comentario-enviar');
  static const claveEditar = Key('publicacion-editar');

  static const noDisponible = 'Esta publicación ya no se encuentra disponible';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicacion = ref.watch(publicacionForoProvider(publicacionId));
    // Ni el administrador comenta lo retenido o eliminado: la policy de
    // insert de `comentarios_foro` lo rechazaría igual.
    final comentable =
        publicacion is AsyncData<PublicacionForo?> &&
        (publicacion.value?.admiteComentarios ?? false);
    final editable =
        publicacion is AsyncData<PublicacionForo?> &&
        (publicacion.value?.editablePor(ref.read(usuarioActualProvider)()) ??
            false);

    void recargar() {
      ref
        ..invalidate(publicacionForoProvider(publicacionId))
        ..invalidate(comentariosForoProvider(publicacionId));
    }

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: 'Publicación',
                onAtras: context.pop,
                accion: editable
                    ? TrazaIconButton(
                        key: claveEditar,
                        icon: Icons.edit_outlined,
                        tooltip: 'Editar publicación',
                        onPressed: () => context.push(_rutaEditar),
                      )
                    : null,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (publicacion) {
                    // Al corredor, lo que no está publicado no le existe:
                    // retenida o eliminada se ven igual que borrada
                    // (criterio 3 de SCRUM-324).
                    AsyncData(value: final p)
                        when p == null ||
                            (!vistaModeracion && !p.admiteComentarios) =>
                      EstadoVacio(
                        icono: Icons.visibility_off_outlined,
                        titulo: noDisponible,
                        detalle:
                            'Puede que la hayan retirado o que esté en '
                            'revisión.',
                        accion: OutlinedButton(
                          onPressed: context.pop,
                          child: const Text('Volver al foro'),
                        ),
                      ),
                    AsyncData(value: final p?) => _Conversacion(
                      publicacion: p,
                      vistaModeracion: vistaModeracion,
                    ),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar la publicación',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: recargar,
                        child: const Text('Reintentar'),
                      ),
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
              if (comentable) _CajaComentario(publicacionId: publicacionId),
            ],
          ),
        ),
      ),
    );
  }
}

/// La publicación entera y, debajo, sus comentarios.
class _Conversacion extends ConsumerWidget {
  const _Conversacion({
    required this.publicacion,
    required this.vistaModeracion,
  });

  final PublicacionForo publicacion;
  final bool vistaModeracion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comentarios = ref.watch(comentariosForoProvider(publicacion.id));
    final ahora = ref.read(relojProvider)();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _Publicacion(
          publicacion: publicacion,
          ahora: ahora,
          conEstado: vistaModeracion,
        ),
        const SizedBox(height: AppSpacing.lg),
        switch (comentarios) {
          AsyncData(value: final lista) => _Comentarios(
            comentarios: lista,
            autorPublicacionId: publicacion.autorId,
            ahora: ahora,
          ),
          AsyncError() => MensajeVacio(
            icono: Icons.cloud_off_outlined,
            titulo: 'No pudimos cargar los comentarios',
            detalle: 'Desliza hacia abajo para intentarlo de nuevo.',
          ),
          _ => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

class _Publicacion extends StatelessWidget {
  const _Publicacion({
    required this.publicacion,
    required this.ahora,
    required this.conEstado,
  });

  final PublicacionForo publicacion;
  final DateTime ahora;
  final bool conEstado;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AvatarAutor(nombre: publicacion.autorNombre, tamano: 40),
            const SizedBox(width: 10),
            Expanded(
              child: _AutorYFecha(
                autor: publicacion.autorNombre,
                fecha: fechaRelativa(publicacion.fechaCreacion, ahora),
                insignias: [
                  if (publicacion.autorEsAdmin)
                    const InsigniaForo.administrador(),
                ],
              ),
            ),
            if (conEstado) EstadoPublicacionChip(estado: publicacion.estado),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          publicacion.titulo,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.18,
            color: AppColors.ink,
            height: 1.3,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          publicacion.contenido,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.ink,
            height: 1.5,
          ),
        ),
        if (conEstado && publicacion.motivoModeracion != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Motivo: ${publicacion.motivoModeracion}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}

class _Comentarios extends StatelessWidget {
  const _Comentarios({
    required this.comentarios,
    required this.autorPublicacionId,
    required this.ahora,
  });

  final List<ComentarioForo> comentarios;

  /// Quién creó la publicación, para marcar sus respuestas con "Autor".
  final String autorPublicacionId;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Text(
            comentarios.isEmpty
                ? 'COMENTARIOS'
                : 'COMENTARIOS (${comentarios.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.ink3,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (comentarios.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Nadie ha comentado todavía. Sé el primero en opinar.',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
          )
        else
          for (final comentario in comentarios)
            _Comentario(
              comentario: comentario,
              esDelAutor: comentario.autorId == autorPublicacionId,
              ahora: ahora,
            ),
      ],
    );
  }
}

class _Comentario extends StatelessWidget {
  const _Comentario({
    required this.comentario,
    required this.esDelAutor,
    required this.ahora,
  });

  final ComentarioForo comentario;
  final bool esDelAutor;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarAutor(nombre: comentario.autorNombre, tamano: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: AppColors.bgAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AutorYFecha(
                    autor: comentario.autorNombre,
                    fecha: fechaRelativa(comentario.fechaCreacion, ahora),
                    enLinea: true,
                    insignias: [
                      if (comentario.autorEsAdmin)
                        const InsigniaForo.administrador(),
                      if (esDelAutor) const InsigniaForo.autor(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comentario.contenido,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.ink,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutorYFecha extends StatelessWidget {
  const _AutorYFecha({
    required this.autor,
    required this.fecha,
    this.enLinea = false,
    this.insignias = const [],
  });

  final String autor;
  final String fecha;

  /// Van pegadas al nombre: "Administrador", "Autor".
  final List<Widget> insignias;

  /// En el comentario van en la misma línea para no robarle alto.
  final bool enLinea;

  @override
  Widget build(BuildContext context) {
    final nombre = Text(
      autor,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
    final cuando = Text(
      fecha,
      style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
    );
    final conInsignias = [
      Flexible(child: nombre),
      for (final insignia in insignias) ...[
        const SizedBox(width: 6),
        Flexible(child: insignia),
      ],
    ];

    if (enLinea) {
      return Row(
        children: [
          ...conInsignias,
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '•',
              style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
            ),
          ),
          cuando,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: conInsignias),
        cuando,
      ],
    );
  }
}

/// La caja fija al pie para escribir un comentario (SCRUM-351 y SCRUM-352).
class _CajaComentario extends ConsumerStatefulWidget {
  const _CajaComentario({required this.publicacionId});

  final String publicacionId;

  @override
  ConsumerState<_CajaComentario> createState() => _CajaComentarioState();
}

class _CajaComentarioState extends ConsumerState<_CajaComentario> {
  final _texto = TextEditingController();

  String? _error;
  bool _enviando = false;

  /// Desde cuántos caracteres se muestra el contador: antes solo estorba.
  static const _avisarDesde = maxCaracteresComentario - 100;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      final resultado = await ref
          .read(comentarioForoProvider)
          .comentar(widget.publicacionId, BorradorComentario(_texto.text));
      if (!mounted) return;

      switch (resultado) {
        case ComentarioRegistrado():
          _texto.clear();
          setState(() => _error = null);
        case ComentarioInvalido(:final error):
          setState(() => _error = error);
        case PublicacionNoDisponible():
          mostrarToast(context, ComentarioPublicacion.noDisponible);
        case ComentarioNoGuardado(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usados = _texto.text.trim().length;
    final hayError = _error != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        10,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: DetallePublicacionScreen.claveCaja,
                  controller: _texto,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    hintText: 'Escribe un comentario…',
                    isDense: true,
                    filled: hayError,
                    fillColor: hayError ? AppColors.dangerTint : null,
                    enabledBorder: hayError ? _bordeError : null,
                    focusedBorder: hayError ? _bordeError : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: DetallePublicacionScreen.claveEnviar,
                onPressed: _enviando ? null : _enviar,
                tooltip: 'Enviar comentario',
                color: AppColors.primary,
                icon: _enviando
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
          if (hayError || usados > _avisarDesde)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                  if (usados > _avisarDesde)
                    Text(
                      '$usados/$maxCaracteresComentario',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: usados > maxCaracteresComentario
                            ? AppColors.danger
                            : AppColors.ink3,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static final _bordeError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
  );
}
