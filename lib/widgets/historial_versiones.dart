import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/publicacion_foro.dart';
import '../services/foro_provider.dart';
import '../services/reloj_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/fecha_relativa.dart';
import 'estado_vacio.dart';

/// Abre el historial de versiones de [publicacion] desde abajo (SCRUM-355).
Future<void> mostrarHistorialVersiones(
  BuildContext context,
  PublicacionForo publicacion,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.bg,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, desplazamiento) => HistorialVersiones(
        publicacion: publicacion,
        desplazamiento: desplazamiento,
      ),
    ),
  );
}

/// Cómo se ha leído una publicación editada: la versión de ahora arriba y
/// debajo las anteriores, hasta la original (SCRUM-355).
///
/// Solo para el administrador: la policy de `versiones_publicacion_foro` no
/// le deja leerlo a nadie más.
class HistorialVersiones extends ConsumerWidget {
  const HistorialVersiones({
    required this.publicacion,
    this.desplazamiento,
    super.key,
  });

  final PublicacionForo publicacion;
  final ScrollController? desplazamiento;

  static const titulo = 'Historial de versiones';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versiones = ref.watch(versionesPublicacionProvider(publicacion.id));
    final ahora = ref.read(relojProvider)();

    return switch (versiones) {
      AsyncData(value: final anteriores) => ListView(
        controller: desplazamiento,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          const Text(
            titulo,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Version(
            etiqueta: 'Versión ${anteriores.length + 1} · actual',
            cuando: fechaYHoraRelativa(
              publicacion.fechaEdicion ?? publicacion.fechaCreacion,
              ahora,
            ),
            titulo: publicacion.titulo,
            contenido: publicacion.contenido,
            actual: true,
          ),
          // Vienen de la más reciente a la original.
          for (final (i, version) in anteriores.indexed)
            _Version(
              etiqueta: i == anteriores.length - 1
                  ? 'Versión 1 · original'
                  : 'Versión ${anteriores.length - i}',
              cuando: fechaYHoraRelativa(version.vigenteDesde, ahora),
              titulo: version.titulo,
              contenido: version.contenido,
            ),
        ],
      ),
      AsyncError() => const MensajeVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No pudimos cargar el historial',
        detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Version extends StatelessWidget {
  const _Version({
    required this.etiqueta,
    required this.cuando,
    required this.titulo,
    required this.contenido,
    this.actual = false,
  });

  final String etiqueta;
  final String cuando;
  final String titulo;
  final String contenido;
  final bool actual;

  @override
  Widget build(BuildContext context) {
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
          Text(
            contenido,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.ink2,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
