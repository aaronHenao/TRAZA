import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/comentario_foro.dart';
import '../models/publicacion_foro.dart';
import '../services/foro_provider.dart';
import '../services/reloj_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/fecha_relativa.dart';
import 'estado_vacio.dart';

/// Abre el historial de versiones de [publicacion] en un modal (SCRUM-355).
Future<void> mostrarHistorialVersiones(
  BuildContext context,
  PublicacionForo publicacion,
) => _mostrar(
  context,
  (desplazamiento) => _HistorialPublicacion(publicacion, desplazamiento),
);

/// Abre el historial de versiones de [comentario] en un modal (SCRUM-356).
Future<void> mostrarHistorialComentario(
  BuildContext context,
  ComentarioForo comentario,
) => _mostrar(
  context,
  (desplazamiento) => _HistorialComentario(comentario, desplazamiento),
);

Future<void> _mostrar(
  BuildContext context,
  Widget Function(ScrollController) contenido,
) {
  return showDialog<void>(
    context: context,
    builder: (contexto) => Dialog(
      backgroundColor: AppColors.bg,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ConstrainedBox(
        // Alto según lo que haya, sin pasar del 80 % de la pantalla.
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(contexto).height * 0.8,
        ),
        child: _ConDesplazamiento(contenido),
      ),
    ),
  );
}

/// Dueño del [ScrollController] de la lista del modal.
class _ConDesplazamiento extends StatefulWidget {
  const _ConDesplazamiento(this.contenido);

  final Widget Function(ScrollController) contenido;

  @override
  State<_ConDesplazamiento> createState() => _ConDesplazamientoState();
}

class _ConDesplazamientoState extends State<_ConDesplazamiento> {
  final _desplazamiento = ScrollController();

  @override
  void dispose() {
    _desplazamiento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.contenido(_desplazamiento);
}

/// Un texto tal como se leía en un momento: la publicación tiene título, el
/// comentario no.
typedef VersionTexto = ({String? titulo, String contenido, DateTime desde});

class _HistorialPublicacion extends ConsumerWidget {
  const _HistorialPublicacion(this.publicacion, this.desplazamiento);

  final PublicacionForo publicacion;
  final ScrollController desplazamiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HistorialVersiones(
      desplazamiento: desplazamiento,
      actual: (
        titulo: publicacion.titulo,
        contenido: publicacion.contenido,
        desde: publicacion.fechaEdicion ?? publicacion.fechaCreacion,
      ),
      anteriores: ref
          .watch(versionesPublicacionProvider(publicacion.id))
          .whenData(
            (versiones) => [
              for (final v in versiones)
                (
                  titulo: v.titulo,
                  contenido: v.contenido,
                  desde: v.vigenteDesde,
                ),
            ],
          ),
    );
  }
}

class _HistorialComentario extends ConsumerWidget {
  const _HistorialComentario(this.comentario, this.desplazamiento);

  final ComentarioForo comentario;
  final ScrollController desplazamiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HistorialVersiones(
      desplazamiento: desplazamiento,
      actual: (
        titulo: null,
        contenido: comentario.contenido,
        desde: comentario.fechaEdicion ?? comentario.fechaCreacion,
      ),
      anteriores: ref
          .watch(versionesComentarioProvider(comentario.id))
          .whenData(
            (versiones) => [
              for (final v in versiones)
                (titulo: null, contenido: v.contenido, desde: v.vigenteDesde),
            ],
          ),
    );
  }
}

/// Cómo se ha leído algo editado del foro: la versión de ahora arriba y
/// debajo las anteriores, hasta la original (SCRUM-355 y SCRUM-356).
///
/// Solo para el administrador: las policies de `versiones_publicacion_foro`
/// y `versiones_comentario_foro` no le dejan leerlo a nadie más.
class HistorialVersiones extends ConsumerWidget {
  const HistorialVersiones({
    required this.actual,
    required this.anteriores,
    this.desplazamiento,
    super.key,
  });

  final VersionTexto actual;

  /// De la más reciente a la original.
  final AsyncValue<List<VersionTexto>> anteriores;

  final ScrollController? desplazamiento;

  static const titulo = 'Historial de versiones';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.read(relojProvider)();

    final cuerpo = switch (anteriores) {
      AsyncData(value: final lista) => ListView(
        controller: desplazamiento,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        children: [
          _Version(
            etiqueta: 'Versión ${lista.length + 1} · actual',
            cuando: fechaYHoraRelativa(actual.desde, ahora),
            version: actual,
            actual: true,
          ),
          for (final (i, version) in lista.indexed)
            _Version(
              etiqueta: i == lista.length - 1
                  ? 'Versión 1 · original'
                  : 'Versión ${lista.length - i}',
              cuando: fechaYHoraRelativa(version.desde, ahora),
              version: version,
            ),
        ],
      ),
      AsyncError() => const MensajeVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No pudimos cargar el historial',
        detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      ),
      _ => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(child: cuerpo),
      ],
    );
  }
}

class _Version extends StatelessWidget {
  const _Version({
    required this.etiqueta,
    required this.cuando,
    required this.version,
    this.actual = false,
  });

  final String etiqueta;
  final String cuando;
  final VersionTexto version;
  final bool actual;

  @override
  Widget build(BuildContext context) {
    final titulo = version.titulo;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: actual ? AppColors.primaryTint : AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$etiqueta • $cuando',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: actual ? AppColors.primaryDark : AppColors.ink3,
            ),
          ),
          const SizedBox(height: 6),
          if (titulo != null) ...[
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            version.contenido,
            style: TextStyle(
              fontSize: 13,
              color: titulo == null ? AppColors.ink : AppColors.ink2,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
