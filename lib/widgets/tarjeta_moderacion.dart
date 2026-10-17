import 'package:flutter/material.dart';

import '../models/moderacion_foro.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../utils/fecha_relativa.dart';
import 'tarjeta_publicacion.dart';
import 'traza_card.dart';

/// Una moderación del foro (SCRUM-322): qué se analizó, cómo quedó, quién lo
/// decidió, cuándo y por qué.
///
/// La ve el administrador en la moderación ([paraElAdmin], SCRUM-337), con
/// el autor, sus faltas y los botones para decidir lo pendiente. La ve el
/// autor en "Mis rechazados" (SCRUM-339), sin nombres de administradores.
class TarjetaModeracion extends StatelessWidget {
  const TarjetaModeracion({
    required this.moderacion,
    this.paraElAdmin = false,
    this.faltasDelAutor,
    this.onAprobar,
    this.onRechazar,
    this.onTap,
    super.key,
  });

  final ModeracionForo moderacion;
  final bool paraElAdmin;

  /// Cuántas faltas tiene el autor (SCRUM-338). Solo para el administrador.
  final int? faltasDelAutor;

  /// Si están, se ofrece decidir: solo en lo que sigue abierto.
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;
  final VoidCallback? onTap;

  static Key claveDe(String id) => Key('moderacion-$id');
  static Key claveAprobar(String id) => Key('moderacion-aprobar-$id');
  static Key claveRechazar(String id) => Key('moderacion-rechazar-$id');

  static String textoFaltas(int faltas) =>
      faltas == 1 ? '1 falta' : '$faltas faltas';

  @override
  Widget build(BuildContext context) {
    final m = moderacion;
    final titulo = m.titulo;
    final motivo = m.motivo;
    final decision = m.fechaDecision;
    final responsable = paraElAdmin
        ? m.responsableParaElAdmin
        : m.responsableParaElAutor;
    final faltas = faltasDelAutor;

    return TrazaCard(
      key: claveDe(m.id),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.queEs.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.ink3,
                  ),
                ),
              ),
              _EstadoModeracionChip(estado: m.estado),
            ],
          ),
          if (paraElAdmin) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                AvatarAutor(nombre: m.autorNombre),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    m.autorNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (faltas != null && faltas > 0)
                  Text(
                    textoFaltas(faltas),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (titulo != null) ...[
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            m.contenido,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.ink2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Lo pendiente lleva la duda de la IA, que es para el
          // administrador; al autor solo se le explica un rechazo.
          if (motivo != null && (paraElAdmin || m.rechazada))
            _Dato(
              etiqueta: m.rechazada ? 'Motivo' : 'Duda de la IA',
              valor: motivo,
              color: m.rechazada ? AppColors.danger : AppColors.accentInk,
            ),
          if (m.rechazada && m.categorias.isNotEmpty)
            _Dato(etiqueta: 'Infracción', valor: m.categorias.join(', ')),
          if (responsable != null)
            _Dato(
              etiqueta: m.rechazada ? 'Rechazada por' : 'Decidida por',
              valor: responsable,
            ),
          if (decision != null)
            _Dato(etiqueta: 'Fecha', valor: fechaExacta(decision))
          else
            _Dato(etiqueta: 'Enviada', valor: fechaExacta(m.fechaSolicitud)),
          if (onAprobar != null || onRechazar != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: claveRechazar(m.id),
                    onPressed: onRechazar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: claveAprobar(m.id),
                    onPressed: onAprobar,
                    child: const Text('Aprobar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, this.color});

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

class _EstadoModeracionChip extends StatelessWidget {
  const _EstadoModeracionChip({required this.estado});

  final EstadoModeracion estado;

  @override
  Widget build(BuildContext context) {
    final (texto, fondo, tinta) = switch (estado) {
      EstadoModeracion.enRevision => (
        'En revisión',
        AppColors.secondaryTint,
        AppColors.secondaryDark,
      ),
      EstadoModeracion.pendiente => (
        'Pendiente',
        AppColors.accentTint,
        AppColors.accentInk,
      ),
      EstadoModeracion.aprobada => (
        'Aprobada',
        AppColors.primaryTint,
        AppColors.primaryDark,
      ),
      EstadoModeracion.rechazada => (
        'Rechazada',
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
