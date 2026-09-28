import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/progresion.dart';
import '../../services/progresion_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/barra_progresion.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// Los requisitos del siguiente nivel (SCRUM-187).
///
/// Responde a una sola pregunta: cuánto me falta para subir. Por eso muestra
/// junto el nivel alcanzado, la experiencia que lleva, el umbral del siguiente
/// y la diferencia entre ambos, que es el dato que el corredor busca.
///
/// Solo consulta: la experiencia la calcula el motor de experiencia y los
/// umbrales los define el administrador (SCRUM-177).
class ProgresionScreen extends ConsumerWidget {
  const ProgresionScreen({super.key});

  static const ruta = '/progresion';

  static const claveNivelActual = Key('progresion-nivel-actual');
  static const claveExperiencia = Key('progresion-experiencia');
  static const claveFaltante = Key('progresion-faltante');
  static const claveAvance = Key('progresion-avance');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progresion = ref.watch(progresionProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: 'Tu progresión',
                onAtras: context.canPop() ? context.pop : null,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(progresionProvider),
                  child: switch (progresion) {
                    AsyncData(value: final datos) when !datos.hayNiveles =>
                      const _SinNiveles(),
                    AsyncData(value: final datos) => _Detalle(
                      progresion: datos,
                    ),
                    AsyncError() => _NoSePudoCargar(
                      onReintentar: () => ref.invalidate(progresionProvider),
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los cuatro datos del criterio 1, en el orden en que se leen: dónde estoy,
/// cuánto llevo, a dónde voy y cuánto me falta.
class _Detalle extends StatelessWidget {
  const _Detalle({required this.progresion});

  final Progresion progresion;

  @override
  Widget build(BuildContext context) {
    final siguiente = progresion.siguienteNivel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        TrazaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Rotulo('NIVEL ACTUAL'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                // Sin nivel alcanzado todavía: se dice, no se deja en blanco.
                progresion.nivelActual?.nombre ?? 'Aún sin nivel',
                key: ProgresionScreen.claveNivelActual,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${progresion.experiencia} XP acumulados',
                key: ProgresionScreen.claveExperiencia,
                style: const TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (siguiente == null)
          const TrazaCard(child: _NivelMaximo())
        else
          TrazaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Rotulo('SIGUIENTE NIVEL'),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        siguiente.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Insignia(texto: '${siguiente.umbralExperiencia} XP'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Lo recorrido del tramo hacia el siguiente nivel, con la
                // barra de progreso del prototipo (`.lv-track`). Refleja la
                // XP nueva: el cierre del entrenamiento invalida la
                // progresión (SCRUM-208).
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    key: ProgresionScreen.claveAvance,
                    value: progresion.avance,
                    minHeight: 8,
                    backgroundColor: AppColors.bgAlt,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Te faltan ${progresion.experienciaFaltante} XP para '
                  'alcanzarlo.',
                  key: ProgresionScreen.claveFaltante,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.ink2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // Lo mismo que dice el texto, pero de un vistazo (SCRUM-188).
                BarraProgresion(progresion: progresion),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ya está arriba del todo: no hay siguiente nivel que pedirle (criterio 3).
class _NivelMaximo extends StatelessWidget {
  const _NivelMaximo();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.emoji_events_outlined, size: 22, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estás en el nivel más alto',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'No hay ninguno por encima por ahora.',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// El administrador todavía no ha creado niveles (criterio 4): se avisa, no se
/// muestra un error.
class _SinNiveles extends StatelessWidget {
  const _SinNiveles();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 60,
      ),
      children: const [
        _Estado(
          icono: Icons.stairs_outlined,
          titulo: 'Todavía no hay niveles',
          detalle:
              'Cuando se configure la progresión, aquí verás cuánto te falta '
              'para el siguiente.',
        ),
      ],
    );
  }
}

class _NoSePudoCargar extends StatelessWidget {
  const _NoSePudoCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 80,
      ),
      children: [
        _Estado(
          icono: Icons.cloud_off_outlined,
          titulo: 'No pudimos cargar tu progresión',
          detalle: 'Revisa tu conexión e inténtalo de nuevo.',
          accion: OutlinedButton(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.66,
        color: AppColors.ink2,
      ),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgAlt,
          ),
          child: Icon(icono, size: 30, color: AppColors.ink3),
        ),
        const SizedBox(height: 12),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          detalle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
        ),
        if (accion != null) ...[const SizedBox(height: AppSpacing.md), accion!],
      ],
    );
  }
}
