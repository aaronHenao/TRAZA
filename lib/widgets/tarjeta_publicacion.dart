import 'package:flutter/material.dart';

import '../models/publicacion_foro.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/fecha_relativa.dart';
import 'traza_card.dart';

/// Una publicación del foro en el listado: autor, fecha, título y el
/// comienzo del contenido (SCRUM-346).
///
/// La usan el foro del corredor y la moderación del administrador. Solo el
/// administrador ve el estado y el motivo ([conEstado]): en el foro todo lo
/// que aparece está publicado, y decirlo en cada tarjeta sería ruido.
class TarjetaPublicacion extends StatelessWidget {
  const TarjetaPublicacion({
    required this.publicacion,
    required this.ahora,
    this.conEstado = false,
    this.onTap,
    super.key,
  });

  final PublicacionForo publicacion;

  /// El mismo instante para todas las tarjetas, para que dos publicaciones
  /// del mismo día no digan "Hoy" y "Ayer" al cruzar la medianoche.
  final DateTime ahora;

  final bool conEstado;
  final VoidCallback? onTap;

  static Key claveDe(String id) => Key('publicacion-$id');

  @override
  Widget build(BuildContext context) {
    final motivo = publicacion.motivoModeracion;

    return TrazaCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarAutor(nombre: publicacion.autorNombre),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            publicacion.autorNombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (publicacion.autorEsAdmin) ...[
                          const SizedBox(width: 6),
                          const Flexible(child: InsigniaForo.administrador()),
                        ],
                      ],
                    ),
                    Text(
                      publicacion.editada
                          ? '${fechaRelativa(publicacion.fechaCreacion, ahora)}'
                                ' • Editada'
                          : fechaRelativa(publicacion.fechaCreacion, ahora),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              if (conEstado) EstadoPublicacionChip(estado: publicacion.estado),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            publicacion.titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            publicacion.contenido,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.ink2,
              height: 1.45,
            ),
          ),
          if (conEstado && motivo != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Motivo: $motivo',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _NumeroComentarios(cuantos: publicacion.numeroComentarios),
        ],
      ),
    );
  }
}

/// Cuántos comentarios tiene, al pie de la tarjeta (SCRUM-324).
class _NumeroComentarios extends StatelessWidget {
  const _NumeroComentarios({required this.cuantos});

  final int cuantos;

  @override
  Widget build(BuildContext context) {
    final texto = switch (cuantos) {
      0 => 'Comentar',
      1 => '1 comentario',
      _ => '$cuantos comentarios',
    };

    return Row(
      children: [
        const Icon(
          Icons.chat_bubble_outline_rounded,
          size: 15,
          color: AppColors.ink3,
        ),
        const SizedBox(width: 5),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.ink2,
          ),
        ),
      ],
    );
  }
}

/// Marca junto al nombre de quien escribe en el foro: si es el administrador
/// (color principal) o el creador de la publicación que se comenta (color
/// secundario).
///
/// Va dentro de un `Flexible`: en pantallas angostas cede espacio antes que
/// desbordar la fila del nombre.
class InsigniaForo extends StatelessWidget {
  const InsigniaForo.administrador({super.key})
    : texto = textoAdministrador,
      color = AppColors.primary;

  const InsigniaForo.autor({super.key})
    : texto = textoAutor,
      color = AppColors.secondary;

  static const textoAdministrador = 'Administrador';
  static const textoAutor = 'Autor';

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Círculo con la inicial del autor. No hay fotos de perfil todavía.
class AvatarAutor extends StatelessWidget {
  const AvatarAutor({required this.nombre, this.tamano = 34, super.key});

  final String nombre;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final limpio = nombre.trim();
    final inicial = limpio.isEmpty ? '?' : limpio.characters.first;

    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryTint,
      ),
      child: Text(
        inicial.toUpperCase(),
        style: TextStyle(
          fontSize: tamano * 0.42,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

/// Pastilla con el estado de una publicación, para el administrador.
class EstadoPublicacionChip extends StatelessWidget {
  const EstadoPublicacionChip({required this.estado, super.key});

  final EstadoPublicacion estado;

  @override
  Widget build(BuildContext context) {
    final (texto, fondo, tinta) = switch (estado) {
      EstadoPublicacion.publicada => (
        'Publicada',
        AppColors.primaryTint,
        AppColors.primaryDark,
      ),
      EstadoPublicacion.retenida => (
        'Retenida',
        AppColors.accentTint,
        AppColors.accentInk,
      ),
      EstadoPublicacion.eliminada => (
        'Eliminada',
        AppColors.dangerTint,
        AppColors.danger,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tinta,
        ),
      ),
    );
  }
}
