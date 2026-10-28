import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/inicio_provider.dart';
import '../services/reloj_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'fila_reto_usuario.dart';
import 'traza_card.dart';

/// El reto en curso en la portada (SCRUM-288, criterio 3 de SCRUM-283).
///
/// Muestra uno: el que se acaba primero, que es el que hay que atender hoy.
/// Cuántos hay en juego ya lo dice el indicador de la semana (SCRUM-287), y
/// todos están a un toque en la sección de Retos.
///
/// La fila es la misma de la sección de Retos y del historial
/// ([FilaRetoUsuario]): trae el nombre, la XP que paga, la barra de avance y el
/// conteo de kilómetros. Verla distinta aquí haría dudar de si habla del mismo
/// reto.
class BloqueRetoActivo extends ConsumerWidget {
  const BloqueRetoActivo({super.key});

  static const clave = Key('inicio-reto-activo');
  static const claveSinRetos = Key('inicio-sin-retos');

  /// A dónde lleva el bloque: a la sección, no al detalle del reto.
  static const rutaRetos = '/retos';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enCurso = ref.watch(retosEnCursoProvider);

    // `go` y no `push`: Retos es una sección de la barra inferior, así que se
    // llega a ella como a las demás y se vuelve por la barra.
    void aRetos() => context.go(rutaRetos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RETO ACTIVO',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.52,
            color: AppColors.ink2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        switch (enCurso) {
          // Sin retos en juego, la invitación: desde aquí se activa uno.
          AsyncData(value: final retos) when retos.isEmpty => _Aviso(
            clave: claveSinRetos,
            texto: 'Activa un reto y empieza a ganar XP.',
            onTap: aRetos,
          ),
          AsyncData(value: final retos) => KeyedSubtree(
            key: clave,
            child: FilaRetoUsuario(
              reto: retos.first,
              ahora: ref.read(relojProvider)(),
              onTap: aRetos,
            ),
          ),
          AsyncError() => const _Aviso(
            texto:
                'No pudimos cargar tus retos. Desliza hacia abajo para '
                'volver a intentarlo.',
          ),
          _ => const _Aviso(texto: 'Cargando tus retos…'),
        },
      ],
    );
  }
}

/// Una línea en tarjeta: la invitación cuando no hay retos, o el aviso de que
/// no se pudieron consultar.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.onTap, this.clave});

  final String texto;
  final VoidCallback? onTap;
  final Key? clave;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      key: clave,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.ink2,
                height: 1.4,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ],
      ),
    );
  }
}
