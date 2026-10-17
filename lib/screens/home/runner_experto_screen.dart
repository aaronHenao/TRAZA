import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/runner_experto.dart';
import '../../services/runner_experto_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// Los requisitos y ventajas de ser Runner Experto (SCRUM-212).
///
/// Se llega desde el perfil. Muestra si el rol está bloqueado, cuánto le falta
/// al corredor en cada requisito y qué gana al alcanzarlo, para que tenga
/// motivos para intentarlo. Solo informa: no otorga el rol.
class RunnerExpertoScreen extends ConsumerWidget {
  const RunnerExpertoScreen({super.key});

  static const ruta = '/runner-experto';

  static const claveEstado = Key('runner-experto-estado');
  static const claveNiveles = Key('runner-experto-niveles');
  static const claveExperiencia = Key('runner-experto-experiencia');
  static const claveAntiguedad = Key('runner-experto-antiguedad');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoRunnerExpertoProvider);

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: 'Runner Experto',
                onAtras: context.canPop() ? context.pop : null,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(estadoRunnerExpertoProvider),
                  // SCRUM-215: la sección nunca queda en blanco.
                  child: switch (estado) {
                    AsyncData(value: final datos) => _Detalle(estado: datos),
                    AsyncError() => _NoSePudoCargar(
                      onReintentar: () =>
                          ref.invalidate(estadoRunnerExpertoProvider),
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

class _Detalle extends StatelessWidget {
  const _Detalle({required this.estado});

  final EstadoRunnerExperto estado;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _Cabecera(desbloqueado: estado.desbloqueado),
        const SizedBox(height: AppSpacing.xl),
        const _Rotulo('REQUISITOS'),
        const SizedBox(height: AppSpacing.sm),
        TrazaCard(
          child: Column(
            children: [
              _Requisito(
                key: RunnerExpertoScreen.claveNiveles,
                icono: Icons.flag_rounded,
                // Se pide superar ese nivel: alcanzar uno más (SCRUM-227).
                titulo:
                    'Superar el nivel '
                    '${RequisitosRunnerExperto.nivelesAlcanzados - 1} del mapa',
                cumplido: estado.cumpleNiveles,
                avance: estado.avanceNiveles,
                detalle: _detalleNiveles(estado),
              ),
              const Divider(height: AppSpacing.xl, color: AppColors.line),
              _Requisito(
                key: RunnerExpertoScreen.claveExperiencia,
                icono: Icons.bolt_rounded,
                titulo:
                    '${formatearMiles(RequisitosRunnerExperto.experiencia)} XP '
                    'acumulados',
                cumplido: estado.cumpleExperiencia,
                avance: estado.avanceExperiencia,
                detalle: estado.cumpleExperiencia
                    ? 'Cumplido: tienes '
                          '${formatearMiles(estado.experiencia)} XP.'
                    : 'Llevas ${formatearMiles(estado.experiencia)} XP. Te '
                          'faltan ${formatearMiles(estado.experienciaFaltante)} '
                          'XP.',
              ),
              const Divider(height: AppSpacing.xl, color: AppColors.line),
              _Requisito(
                key: RunnerExpertoScreen.claveAntiguedad,
                icono: Icons.event_available_outlined,
                titulo:
                    '${RequisitosRunnerExperto.mesesDeAntiguedad} meses usando '
                    'TRAZA',
                cumplido: estado.cumpleAntiguedad,
                avance: estado.avanceAntiguedad,
                detalle: _detalleAntiguedad(estado),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const _Rotulo('VENTAJAS'),
        const SizedBox(height: AppSpacing.sm),
        TrazaCard(
          child: Column(
            children: [
              for (final (i, ventaja)
                  in VentajaRunnerExperto.values.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                _Ventaja(ventaja),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _detalleNiveles(EstadoRunnerExperto estado) {
    final actual = estado.nivelActual;
    if (estado.cumpleNiveles) {
      return 'Cumplido: vas en el nivel ${estado.nivelesAlcanzados}, '
          '${actual!.nombre}.';
    }

    final dondeVa = actual == null
        ? 'Aún no alcanzas el primer nivel.'
        : 'Vas en el nivel ${estado.nivelesAlcanzados}, ${actual.nombre}.';
    final faltan = estado.nivelesFaltantes;
    final cuantos = faltan == 1
        ? 'Te falta 1 nivel.'
        : 'Te faltan $faltan niveles.';
    // Sin esto parecería que basta con correr, y el mapa no llega tan lejos.
    final enMapa = !estado.faltanNivelesEnMapa
        ? ''
        : estado.nivelesEnMapa == 0
        ? ' Por ahora el mapa no tiene niveles.'
        : ' Por ahora el mapa tiene ${estado.nivelesEnMapa} '
              '${estado.nivelesEnMapa == 1 ? 'nivel' : 'niveles'}.';
    return '$dondeVa $cuantos$enMapa';
  }

  static String _detalleAntiguedad(EstadoRunnerExperto estado) {
    final desde = formatearFecha(estado.fechaRegistro);
    if (estado.cumpleAntiguedad) return 'Cumplido: usas TRAZA desde el $desde.';

    final dias = estado.diasFaltantes;
    return 'Usas TRAZA desde el $desde. Lo cumples el '
        '${formatearFecha(estado.cumpleAntiguedadEl)} '
        '(${dias == 1 ? 'falta 1 día' : 'faltan $dias días'}).';
  }
}

/// La insignia con el estado del rol: bloqueado (atenuada, con candado) o
/// desbloqueado (SCRUM-214).
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.desbloqueado});

  final bool desbloqueado;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.md),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: desbloqueado ? AppColors.accent : AppColors.bgAlt,
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 44,
                color: desbloqueado ? AppColors.accentInk : AppColors.ink3,
              ),
            ),
            if (!desbloqueado)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bg,
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: AppColors.ink2,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          key: RunnerExpertoScreen.claveEstado,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: desbloqueado ? AppColors.accentTint : AppColors.bgAlt,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            desbloqueado ? 'Desbloqueado' : 'Bloqueado',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: desbloqueado ? AppColors.accentInk : AppColors.ink2,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          desbloqueado
              ? 'Cumples los requisitos para ser Runner Experto.'
              : 'Cumple los tres requisitos para desbloquear el rol.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
      ],
    );
  }
}

class _Requisito extends StatelessWidget {
  const _Requisito({
    required this.icono,
    required this.titulo,
    required this.cumplido,
    required this.avance,
    required this.detalle,
    super.key,
  });

  final IconData icono;
  final String titulo;
  final bool cumplido;
  final double avance;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icono, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Icon(
              cumplido
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: cumplido ? AppColors.primary : AppColors.ink3,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: avance,
            minHeight: 8,
            backgroundColor: AppColors.bgAlt,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          detalle,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.ink2,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Ventaja extends StatelessWidget {
  const _Ventaja(this.ventaja);

  final VentajaRunnerExperto ventaja;

  IconData get _icono => switch (ventaja) {
    VentajaRunnerExperto.evaluarRutas => Icons.star_rate_rounded,
    VentajaRunnerExperto.insignia => Icons.workspace_premium_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_icono, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ventaja.titulo,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ventaja.detalle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.ink2,
                  height: 1.4,
                ),
              ),
            ],
          ),
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
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgAlt,
          ),
          child: const Icon(
            Icons.cloud_off_outlined,
            size: 30,
            color: AppColors.ink3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'No pudimos cargar tu estado',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Revisa tu conexión e inténtalo de nuevo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: OutlinedButton(
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

/// 150000 → "150.000", como se escriben las cifras en Colombia.
@visibleForTesting
String formatearMiles(int valor) {
  final digitos = valor.abs().toString();
  final grupos = <String>[];
  for (var fin = digitos.length; fin > 0; fin -= 3) {
    grupos.insert(0, digitos.substring(fin < 3 ? 0 : fin - 3, fin));
  }
  return '${valor < 0 ? '-' : ''}${grupos.join('.')}';
}

/// "15 de marzo de 2026".
@visibleForTesting
String formatearFecha(DateTime fecha) =>
    '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year}';

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
