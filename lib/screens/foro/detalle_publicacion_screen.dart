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
import '../../widgets/historial_versiones.dart';
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
  static const claveEditada = Key('publicacion-editada');

  // Editar comentarios (SCRUM-356).
  static Key claveEditarComentario(String id) => Key('comentario-editar-$id');
  static Key claveComentarioEditado(String id) => Key('comentario-editado-$id');
  static const claveCajaEdicion = Key('comentario-caja-edicion');
  static const claveGuardarEdicion = Key('comentario-guardar-edicion');
  static const claveConfirmarEdicionComentario = Key(
    'comentario-confirmar-edicion',
  );
  static const comentarioEditado = 'Comentario actualizado';

  static const noDisponible = 'Esta publicación ya no se encuentra disponible';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SCRUM-357: comentarios y ediciones aparecen sin refrescar.
    ref.watch(publicacionEnVivoProvider(publicacionId));
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
    final usuario = ref.read(usuarioActualProvider)();

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
          vistaModeracion: vistaModeracion,
        ),
        const SizedBox(height: AppSpacing.lg),
        switch (comentarios) {
          AsyncData(value: final lista) => _Comentarios(
            comentarios: lista,
            autorPublicacionId: publicacion.autorId,
            ahora: ahora,
            // Se edita lo propio y solo mientras la publicación se pueda
            // comentar: la misma regla de la policy de update.
            editablesPor: publicacion.admiteComentarios ? usuario : null,
            vistaModeracion: vistaModeracion,
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
    required this.vistaModeracion,
  });

  final PublicacionForo publicacion;
  final DateTime ahora;

  /// El administrador ve además el estado, el motivo y el historial de
  /// versiones.
  final bool vistaModeracion;

  @override
  Widget build(BuildContext context) {
    final fecha = fechaRelativa(publicacion.fechaCreacion, ahora);
    // SCRUM-355: todos ven que se editó; solo el administrador abre el
    // historial, y solo a él se lo deja leer la base.
    final conHistorial = publicacion.editada && vistaModeracion;

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
                fecha: publicacion.editada && !conHistorial
                    ? '$fecha • Editada'
                    : fecha,
                insignias: [
                  if (publicacion.autorEsAdmin)
                    const InsigniaForo.administrador(),
                ],
                onEditada: conHistorial
                    ? () => mostrarHistorialVersiones(context, publicacion)
                    : null,
              ),
            ),
            if (vistaModeracion)
              EstadoPublicacionChip(estado: publicacion.estado),
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
        if (vistaModeracion && publicacion.motivoModeracion != null) ...[
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
    required this.editablesPor,
    required this.vistaModeracion,
  });

  final List<ComentarioForo> comentarios;

  /// Quién creó la publicación, para marcar sus respuestas con "Autor".
  final String autorPublicacionId;
  final DateTime ahora;

  /// Quién puede editar sus comentarios ahora, o null si nadie.
  final String? editablesPor;

  /// El administrador abre el historial de lo editado.
  final bool vistaModeracion;

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
              editable: comentario.editablePor(editablesPor),
              vistaModeracion: vistaModeracion,
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
    required this.editable,
    required this.vistaModeracion,
  });

  final ComentarioForo comentario;
  final bool esDelAutor;
  final DateTime ahora;
  final bool editable;
  final bool vistaModeracion;

  @override
  Widget build(BuildContext context) {
    final fecha = fechaRelativa(comentario.fechaCreacion, ahora);
    // SCRUM-356: todos ven que se editó; solo el administrador abre el
    // historial.
    final conHistorial = comentario.editado && vistaModeracion;

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
                  Row(
                    children: [
                      Expanded(
                        child: _AutorYFecha(
                          autor: comentario.autorNombre,
                          fecha: comentario.editado && !conHistorial
                              ? '$fecha • Editado'
                              : fecha,
                          enLinea: true,
                          insignias: [
                            if (comentario.autorEsAdmin)
                              const InsigniaForo.administrador(),
                            if (esDelAutor) const InsigniaForo.autor(),
                          ],
                          onEditada: conHistorial
                              ? () => mostrarHistorialComentario(
                                  context,
                                  comentario,
                                )
                              : null,
                          textoEdicion: 'Editado',
                          claveEdicion:
                              DetallePublicacionScreen.claveComentarioEditado(
                                comentario.id,
                              ),
                        ),
                      ),
                      if (editable)
                        SizedBox.square(
                          dimension: 28,
                          child: IconButton(
                            key: DetallePublicacionScreen.claveEditarComentario(
                              comentario.id,
                            ),
                            onPressed: () =>
                                _editarComentario(context, comentario),
                            tooltip: 'Editar comentario',
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            color: AppColors.ink3,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
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
    this.onEditada,
    this.textoEdicion = 'Editada',
    this.claveEdicion = DetallePublicacionScreen.claveEditada,
  });

  final String autor;
  final String fecha;

  /// Para el administrador, si se editó: junto a la fecha va "Editada" (o
  /// "Editado", [textoEdicion]) y al tocarlo se abre su historial.
  final VoidCallback? onEditada;
  final String textoEdicion;
  final Key claveEdicion;

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
    final soloFecha = Text(
      fecha,
      style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
    );
    final alEditada = onEditada;
    final cuando = alEditada == null
        ? soloFecha
        : Row(
            children: [
              soloFecha,
              const Text(
                ' • ',
                style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
              ),
              InkWell(
                key: claveEdicion,
                onTap: alEditada,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    textoEdicion,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
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

/// Abre desde abajo la caja para editar [comentario] (SCRUM-356).
Future<void> _editarComentario(
  BuildContext context,
  ComentarioForo comentario,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.bg,
    builder: (contexto) => Padding(
      // Que el teclado no tape la caja.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(contexto).bottom,
      ),
      child: _EditarComentario(comentario: comentario),
    ),
  );
}

/// Editar un comentario propio: las mismas reglas que al comentar y una
/// confirmación antes de guardar (SCRUM-356).
class _EditarComentario extends ConsumerStatefulWidget {
  const _EditarComentario({required this.comentario});

  final ComentarioForo comentario;

  @override
  ConsumerState<_EditarComentario> createState() => _EditarComentarioState();
}

class _EditarComentarioState extends ConsumerState<_EditarComentario> {
  late final _texto = TextEditingController(text: widget.comentario.contenido);

  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final borrador = BorradorComentario(_texto.text);

    // Primero las reglas: no tiene sentido confirmar algo que no se puede
    // guardar.
    final error = borrador.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_texto.text.trim() == widget.comentario.contenido) {
      Navigator.of(context).pop();
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Guardar los cambios?'),
        content: const Text(
          'El comentario quedará marcado como editado y la versión anterior '
          'quedará guardada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: DetallePublicacionScreen.claveConfirmarEdicionComentario,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    try {
      final resultado = await ref
          .read(edicionComentarioProvider)
          .editar(widget.comentario, borrador);
      if (!mounted) return;

      switch (resultado) {
        case ComentarioEditado():
          Navigator.of(context).pop();
          mostrarToast(context, DetallePublicacionScreen.comentarioEditado);
        case EdicionComentarioInvalida(:final error):
          setState(() => _error = error);
        case EdicionComentarioNoDisponible():
          Navigator.of(context).pop();
          mostrarToast(context, EdicionComentario.noDisponible);
        case EdicionComentarioNoGuardada(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usados = _texto.text.trim().length;
    final error = _error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Editar comentario',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: DetallePublicacionScreen.claveCajaEdicion,
            controller: _texto,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              filled: error != null,
              fillColor: error != null ? AppColors.dangerTint : null,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  error ?? '',
                  style: const TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ),
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
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  key: DetallePublicacionScreen.claveGuardarEdicion,
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ],
      ),
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
