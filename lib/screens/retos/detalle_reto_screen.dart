import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/periodicidad_reto.dart';
import '../../models/reto.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/tarjeta_reto.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// Abre el detalle del reto que pide la ruta.
///
/// El listado pasa el reto en `extra` para no volver a consultarlo. Si no
/// viene —por ejemplo al abrir la ruta directamente— se busca entre los
/// vigentes que ya están cargados.
class DetalleRetoPorRuta extends ConsumerWidget {
  const DetalleRetoPorRuta({required this.retoId, this.reto, super.key});

  final String retoId;
  final Reto? reto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reto =
        this.reto ??
        ref
            .watch(retosVigentesProvider)
            .valueOrNull
            ?.where((candidato) => candidato.id == retoId)
            .firstOrNull;

    if (reto == null) return const _NoEncontrado();
    return DetalleRetoScreen(reto: reto);
  }
}

class _NoEncontrado extends StatelessWidget {
  const _NoEncontrado();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TrazaTopBar(titulo: 'Reto', onAtras: context.pop),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    'Este reto ya no está disponible.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: AppColors.ink2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalle de un reto (SCRUM-165).
///
/// Responde lo que el criterio 3 de SCRUM-135 pide: el objetivo del reto y
/// las condiciones para cumplirlo, para que el corredor decida si lo intenta.
/// Activarlo es de SCRUM-136.
class DetalleRetoScreen extends ConsumerWidget {
  const DetalleRetoScreen({required this.reto, super.key});

  final Reto reto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = ref.read(relojProvider)();

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Reto', onAtras: context.pop),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  children: [
                    _Encabezado(reto: reto),
                    const SizedBox(height: AppSpacing.lg),
                    _Condiciones(reto: reto, hoy: hoy),
                    const SizedBox(height: AppSpacing.md),
                    _Descripcion(reto: reto),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El icono, el nombre y la XP: de un vistazo, qué reto es y qué da.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.reto});

  final Reto reto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconoPeriodicidad(periodicidad: reto.periodicidad),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reto.nombre,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  InsigniaReto(
                    texto: '+${reto.xpOtorgada} XP',
                    fondo: AppColors.primaryTint,
                    color: AppColors.primaryDark,
                  ),
                  InsigniaReto(texto: reto.periodicidad.etiqueta),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lo que hay que hacer para cumplirlo, en datos concretos.
class _Condiciones extends StatelessWidget {
  const _Condiciones({required this.reto, required this.hoy});

  final Reto reto;
  final DateTime hoy;

  static const _meses = [
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

  static String _fecha(DateTime dia) =>
      '${dia.day} de ${_meses[dia.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final quedan = reto.vigencia.diasRestantesDesde(hoy);

    return TrazaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PARA CUMPLIRLO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.66,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _Fila(
            icono: Icons.flag_outlined,
            titulo: 'Recorre ${TarjetaReto.textoKm(reto.metaKm)} km',
            detalle: switch (reto.periodicidad) {
              PeriodicidadReto.diaria => 'Durante el día de hoy.',
              PeriodicidadReto.semanal =>
                'Sumando lo de toda la semana, en las salidas que quieras.',
              PeriodicidadReto.mensual =>
                'Sumando lo de todo el mes, en las salidas que quieras.',
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _Fila(
            icono: Icons.calendar_today_outlined,
            titulo: reto.vigencia.dias == 1
                ? 'Solo hoy, ${_fecha(reto.vigencia.inicio)}'
                : 'Del ${_fecha(reto.vigencia.inicio)} al '
                      '${_fecha(reto.vigencia.fin)}',
            detalle: switch (quedan) {
              0 => 'La vigencia de este reto ya terminó.',
              1 => 'Es el último día: termina esta noche.',
              2 => 'Queda 1 día.',
              _ => 'Quedan ${quedan - 1} días.',
            },
            // El último día se resalta: es lo que cambia la decisión.
            destacado: quedan == 1,
          ),
          const SizedBox(height: AppSpacing.md),
          _Fila(
            icono: Icons.military_tech_outlined,
            titulo: 'Ganas ${reto.xpOtorgada} XP',
            detalle: 'Se acreditan al completarlo.',
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.destacado = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final color = destacado ? AppColors.danger : AppColors.ink2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: TextStyle(fontSize: 12.5, color: color, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lo que escribió el administrador, tal cual.
class _Descripcion extends StatelessWidget {
  const _Descripcion({required this.reto});

  final Reto reto;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DESCRIPCIÓN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.66,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reto.descripcion,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.ink,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
