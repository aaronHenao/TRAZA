import 'package:flutter/material.dart';

import '../models/revision_ruta.dart';
import '../models/ruta.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/fecha_relativa.dart';
import 'tarjeta_publicacion.dart' show AvatarAutor;
import 'tarjeta_reto.dart' show TarjetaReto;
import 'tarjeta_ruta.dart';
import 'traza_card.dart';

/// Una ruta en la bandeja de un revisor (SCRUM-327 y SCRUM-329).
///
/// Enseña lo que hay que mirar para decidir: de quién es, cómo se llama, qué
/// dice de ella su autor y cuánto mide. El trazado no va aquí, porque un mapa
/// dentro de una lista se pelea con el desplazamiento: se ve al tocarla.
class TarjetaRevisionRuta extends StatelessWidget {
  const TarjetaRevisionRuta({
    required this.ruta,
    this.onAprobar,
    this.onRechazar,
    this.onTap,
    super.key,
  });

  final Ruta ruta;

  /// Si están, se ofrece decidir desde la propia tarjeta.
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;
  final VoidCallback? onTap;

  static Key claveDe(String id) => Key('revision-ruta-$id');
  static Key claveAprobar(String id) => Key('revision-ruta-aprobar-$id');
  static Key claveRechazar(String id) => Key('revision-ruta-rechazar-$id');

  @override
  Widget build(BuildContext context) {
    final descripcion = ruta.descripcion?.trim();
    final km = ruta.distanciaKm;

    return TrazaCard(
      key: claveDe(ruta.id),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarAutor(nombre: ruta.autorNombre),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ruta.autorNombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.ink3,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            ruta.nombre,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          if (descripcion != null && descripcion.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              descripcion,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.ink2,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          DatoRevision(etiqueta: 'Estado', valor: ruta.estado.etiqueta),
          DatoRevision(
            etiqueta: 'Distancia',
            valor: km == null
                ? TarjetaRuta.sinDistancia
                : '${TarjetaReto.textoKm(km)} km',
          ),
          DatoRevision(
            etiqueta: 'Enviada',
            valor: fechaExacta(ruta.fechaCreacion),
          ),
          if (onAprobar != null || onRechazar != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BotonesRevision(
              claveAprobar: claveAprobar(ruta.id),
              claveRechazar: claveRechazar(ruta.id),
              onAprobar: onAprobar,
              onRechazar: onRechazar,
            ),
          ],
        ],
      ),
    );
  }
}

/// "Etiqueta: valor" en pequeño, como los datos de una moderación.
class DatoRevision extends StatelessWidget {
  const DatoRevision({
    required this.etiqueta,
    required this.valor,
    this.color,
    super.key,
  });

  final String etiqueta;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$etiqueta: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: valor),
          ],
        ),
        style: TextStyle(fontSize: 12, color: color ?? AppColors.ink2),
      ),
    );
  }
}

/// Rechazar a la izquierda y aprobar a la derecha, como en la moderación del
/// foro.
class BotonesRevision extends StatelessWidget {
  const BotonesRevision({
    required this.claveAprobar,
    required this.claveRechazar,
    this.onAprobar,
    this.onRechazar,
    super.key,
  });

  final Key claveAprobar;
  final Key claveRechazar;
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: claveRechazar,
            onPressed: onRechazar,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Rechazar'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton(
            key: claveAprobar,
            onPressed: onAprobar,
            child: const Text('Aprobar'),
          ),
        ),
      ],
    );
  }
}
