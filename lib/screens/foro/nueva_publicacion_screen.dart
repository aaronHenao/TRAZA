import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/borrador_publicacion.dart';
import '../../models/publicacion_foro.dart';
import '../../services/foro_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Formulario para publicar en el foro (SCRUM-344), con la validación de
/// título, contenido y límite de caracteres (SCRUM-345).
///
/// El administrador usa el mismo formulario desde la moderación
/// ([rutaAdmin], SCRUM-354), y el autor lo usa para editar lo suyo
/// ([editando], SCRUM-355).
class NuevaPublicacionScreen extends ConsumerStatefulWidget {
  const NuevaPublicacionScreen({this.editando, super.key});

  /// La publicación que se edita, o null para una nueva.
  final PublicacionForo? editando;

  static const ruta = '/foro/nueva';
  static const rutaAdmin = '/admin/foro/nueva';

  static const claveTitulo = Key('publicacion-titulo');
  static const claveContenido = Key('publicacion-contenido');
  static const clavePublicar = Key('publicacion-publicar');

  static const publicada = 'Publicación creada';
  static const enRevision =
      'Tu publicación está en revisión. Aparecerá en el foro cuando se '
      'apruebe.';
  static const editada = 'Publicación actualizada';
  static const edicionEnRevision =
      'Tus cambios están en revisión. Mientras tanto se ve la versión '
      'anterior.';
  static const sinCambios = 'No hay cambios para guardar';

  static const claveConfirmarEdicion = Key('publicacion-confirmar-edicion');

  @override
  ConsumerState<NuevaPublicacionScreen> createState() =>
      _NuevaPublicacionScreenState();
}

class _NuevaPublicacionScreenState
    extends ConsumerState<NuevaPublicacionScreen> {
  late final _titulo = TextEditingController(text: widget.editando?.titulo);
  late final _contenido = TextEditingController(
    text: widget.editando?.contenido,
  );

  /// Los errores solo se pintan después del primer intento de publicar:
  /// marcar en rojo lo que todavía no se ha escrito sería regañar por
  /// adelantado.
  Map<CampoPublicacion, String> _errores = const {};

  bool _publicando = false;

  @override
  void dispose() {
    _titulo.dispose();
    _contenido.dispose();
    super.dispose();
  }

  /// Quita el error de un campo en cuanto se toca, y repinta el contador.
  void _alEditar(CampoPublicacion campo) {
    setState(() {
      if (_errores.containsKey(campo)) {
        _errores = {..._errores}..remove(campo);
      }
    });
  }

  Future<void> _publicar() async {
    final editando = widget.editando;
    if (editando != null) return _guardarCambios(editando);

    if (_publicando) return;
    setState(() => _publicando = true);
    try {
      final resultado = await ref
          .read(creacionPublicacionProvider)
          .publicar(
            BorradorPublicacion(
              titulo: _titulo.text,
              contenido: _contenido.text,
            ),
          );
      if (!mounted) return;

      switch (resultado) {
        case PublicacionCreada():
          context.pop();
          mostrarToast(context, NuevaPublicacionScreen.publicada);
        case PublicacionEnRevision():
          context.pop();
          mostrarToast(context, NuevaPublicacionScreen.enRevision);
        case PublicacionConErrores(:final errores):
          setState(() => _errores = errores);
          mostrarToast(context, 'Revisa los campos marcados');
        case PublicacionNoGuardada(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  /// Guarda la edición (SCRUM-355). Pide confirmación antes, porque lo que
  /// todos leen cambia y la publicación queda marcada como editada.
  Future<void> _guardarCambios(PublicacionForo original) async {
    if (_publicando) return;
    final borrador = BorradorPublicacion(
      titulo: _titulo.text,
      contenido: _contenido.text,
    );

    // Primero las reglas: no tiene sentido confirmar algo que no se puede
    // guardar.
    if (!borrador.esValido) {
      setState(() => _errores = borrador.errores);
      mostrarToast(context, 'Revisa los campos marcados');
      return;
    }
    if (borrador.titulo.trim() == original.titulo &&
        borrador.contenido.trim() == original.contenido) {
      mostrarToast(context, NuevaPublicacionScreen.sinCambios);
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Guardar los cambios?'),
        content: Text(
          original.autorEsAdmin
              ? 'La publicación quedará marcada como editada y la versión '
                    'anterior quedará guardada.'
              // SCRUM-322: lo del corredor pasa por la moderación.
              : 'Los cambios pasarán por revisión antes de verse en el foro. '
                    'Mientras tanto, todos verán la versión actual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: NuevaPublicacionScreen.claveConfirmarEdicion,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _publicando = true);
    try {
      final resultado = await ref
          .read(edicionPublicacionProvider)
          .editar(original.id, borrador);
      if (!mounted) return;

      switch (resultado) {
        case PublicacionEditada():
          context.pop();
          mostrarToast(context, NuevaPublicacionScreen.editada);
        case EdicionEnRevision():
          context.pop();
          mostrarToast(context, NuevaPublicacionScreen.edicionEnRevision);
        case EdicionConErrores(:final errores):
          setState(() => _errores = errores);
          mostrarToast(context, 'Revisa los campos marcados');
        case EdicionNoDisponible():
          context.pop();
          mostrarToast(context, EdicionPublicacion.noDisponible);
        case EdicionNoGuardada(:final mensaje):
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.editando != null;

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: editando ? 'Editar publicación' : 'Nueva publicación',
                onAtras: context.pop,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    _Campo(
                      clave: NuevaPublicacionScreen.claveTitulo,
                      etiqueta: 'Título',
                      controlador: _titulo,
                      pista: '¿Cómo preparo mi primera media maratón?',
                      error: _errores[CampoPublicacion.titulo],
                      maxCaracteres: maxCaracteresTituloPublicacion,
                      onCambio: () => _alEditar(CampoPublicacion.titulo),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Campo(
                      clave: NuevaPublicacionScreen.claveContenido,
                      etiqueta: 'Contenido',
                      controlador: _contenido,
                      pista:
                          'Cuenta tu duda o tu experiencia para que la '
                          'comunidad pueda responderte.',
                      error: _errores[CampoPublicacion.contenido],
                      maxCaracteres: maxCaracteresContenidoPublicacion,
                      lineas: 8,
                      onCambio: () => _alEditar(CampoPublicacion.contenido),
                    ),
                  ],
                ),
              ),
              _Pie(
                texto: editando ? 'Guardar cambios' : 'Publicar',
                publicando: _publicando,
                onPublicar: _publicar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo con su etiqueta, su contador de caracteres y, cuando lo hay, su
/// error debajo.
///
/// El límite no se impone cortando lo que se escribe: si el texto se truncara
/// en silencio, el usuario perdería parte de lo que pegó sin enterarse. Se le
/// deja pasarse y se le dice cuánto sobra (criterio 2 de SCRUM-323).
class _Campo extends StatelessWidget {
  const _Campo({
    required this.clave,
    required this.etiqueta,
    required this.controlador,
    required this.pista,
    required this.maxCaracteres,
    required this.onCambio,
    this.error,
    this.lineas = 1,
  });

  final Key clave;
  final String etiqueta;
  final TextEditingController controlador;
  final String pista;
  final int maxCaracteres;
  final VoidCallback onCambio;
  final String? error;
  final int lineas;

  @override
  Widget build(BuildContext context) {
    final hayError = error != null;
    final usados = controlador.text.trim().length;
    final pasado = usados > maxCaracteres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '$usados/$maxCaracteres',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: pasado ? FontWeight.w700 : FontWeight.w500,
                color: pasado ? AppColors.danger : AppColors.ink3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          key: clave,
          controller: controlador,
          onChanged: (_) => onCambio(),
          minLines: lineas,
          maxLines: lineas == 1 ? 1 : null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: pista,
            filled: hayError,
            fillColor: hayError ? AppColors.dangerTint : null,
            enabledBorder: hayError ? _bordeError : null,
            focusedBorder: hayError ? _bordeError : null,
          ),
        ),
        if (hayError) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  static final _bordeError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
  );
}

class _Pie extends StatelessWidget {
  const _Pie({
    required this.texto,
    required this.publicando,
    required this.onPublicar,
  });

  final String texto;
  final bool publicando;
  final VoidCallback onPublicar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        12,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: FilledButton(
        key: NuevaPublicacionScreen.clavePublicar,
        onPressed: publicando ? null : onPublicar,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: publicando
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(texto),
      ),
    );
  }
}
