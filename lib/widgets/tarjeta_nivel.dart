import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/progresion.dart';
import '../screens/home/mapa_progresion_screen.dart';
import '../services/progresion_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'barra_progresion.dart';
import 'traza_card.dart';

/// El nivel del corredor en la portada (SCRUM-286, criterio 1 de SCRUM-283).
///
/// Dice de un vistazo lo que antes había que ir a buscar: en qué nivel va y
/// cómo se llama, cuánta experiencia lleva, cuánta le falta para el siguiente
/// y, con la barra, qué parte del tramo tiene recorrida. Al tocarla se abre el
/// mapa de progresión (SCRUM-226), donde se ve el camino completo.
///
/// Solo consulta: la experiencia la acredita el motor de experiencia y los
/// umbrales los registra el administrador (SCRUM-177). Aquí no se calcula
/// nada; la cuenta la hace [Progresion].
class TarjetaNivel extends ConsumerWidget {
  const TarjetaNivel({super.key});

  static const clave = Key('inicio-tarjeta-nivel');
  static const claveNivel = Key('inicio-nivel-actual');
  static const claveExperiencia = Key('inicio-experiencia');
  static const claveFaltante = Key('inicio-faltante');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progresion = ref.watch(progresionProvider);

    return TrazaCard(
      key: clave,
      // `go` y no `push`: el mapa es una sección de la barra inferior, así que
      // se llega a él como a las demás y se vuelve por la barra.
      onTap: () => context.go(MapaProgresionScreen.ruta),
      child: switch (progresion) {
        AsyncData(value: final datos) when !datos.hayNiveles => const _Aviso(
          titulo: 'Todavía no hay niveles',
          detalle: 'Cuando se configure la progresión, aquí verás tu nivel.',
        ),
        AsyncData(value: final datos) => _Nivel(progresion: datos),
        AsyncError() => const _Aviso(
          titulo: 'No pudimos cargar tu nivel',
          detalle: 'Desliza hacia abajo para volver a intentarlo.',
        ),
        _ => const _Aviso(titulo: 'Cargando tu nivel…', detalle: ''),
      },
    );
  }
}

/// Los datos del criterio 1, en el orden en que se leen: en qué nivel voy,
/// cuánto llevo, cuánto me falta y qué parte del tramo tengo hecha.
class _Nivel extends StatelessWidget {
  const _Nivel({required this.progresion});

  final Progresion progresion;

  @override
  Widget build(BuildContext context) {
    final actual = progresion.nivelActual;
    final siguiente = progresion.siguienteNivel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // Sin ningún nivel alcanzado no hay número que mostrar: se
                // dice, como en Tu progresión, en vez de inventar un "0".
                actual == null ? 'TU NIVEL' : 'NIVEL ${progresion.numeroNivel}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.66,
                  color: AppColors.ink2,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          actual?.nombre ?? 'Aún sin nivel',
          key: TarjetaNivel.claveNivel,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${progresion.experiencia} XP acumulados',
          key: TarjetaNivel.claveExperiencia,
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
        if (siguiente == null)
          // Ya está arriba del todo (criterio 3 de SCRUM-178): no hay tramo
          // que dibujar ni falta que contar.
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Estás en el nivel más alto',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Te faltan ${progresion.experienciaFaltante} XP para '
            '${siguiente.nombre}.',
            key: TarjetaNivel.claveFaltante,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          BarraProgresion(progresion: progresion),
        ],
      ],
    );
  }
}

/// Cargando, sin niveles o sin poder consultar: la tarjeta sigue en su sitio y
/// dice qué pasa, sin romper la portada ni dejar un hueco.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (detalle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            detalle,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink2,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
