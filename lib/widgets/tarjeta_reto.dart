import 'package:flutter/material.dart';

import '../models/periodicidad_reto.dart';
import '../models/reto.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// Un reto del catálogo, como lo ve el corredor (SCRUM-167).
///
/// Muestra lo que necesita para decidir si lo intenta: qué hay que hacer,
/// cuánta XP da y **cuánto le queda de vigencia**, que es lo que cambia la
/// decisión — no es lo mismo un reto que termina esta noche que uno al que le
/// quedan tres semanas.
class TarjetaReto extends StatelessWidget {
  const TarjetaReto({
    required this.reto,
    required this.hoy,
    this.onTap,
    this.bloqueo,
    super.key,
  });

  final Reto reto;

  /// Desde cuándo se cuenta lo que queda. Se recibe en vez de leer el reloj
  /// aquí para que la lista entera use el mismo día.
  final DateTime hoy;

  /// Abre el detalle del reto (SCRUM-166).
  final VoidCallback? onTap;

  /// Por qué hoy no se puede activar, o null si sí se puede. La tarjeta se
  /// sigue pudiendo abrir: el reto existe y sus condiciones se pueden leer,
  /// lo que no se puede es tomarlo ahora.
  final String? bloqueo;

  static Key claveDe(String retoId) => Key('reto-$retoId');

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reto.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InsigniaReto(
                texto: '+${reto.xpOtorgada} XP',
                fondo: AppColors.primaryTint,
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              InsigniaReto(texto: reto.periodicidad.etiqueta),
              InsigniaReto(texto: reto.tipoActividad.nombre),
              InsigniaReto(texto: 'Meta ${textoKm(reto.metaKm)} km'),
              _Vigencia(reto: reto, hoy: hoy),
            ],
          ),
          if (bloqueo != null) ...[
            const SizedBox(height: 10),
            _Bloqueo(motivo: bloqueo!),
          ],
        ],
      ),
    );
  }

  /// Kilómetros legibles: `5` en vez de `5.0`, `2.5` se mantiene y
  /// `0.3333333333` se queda en `0.33`.
  ///
  /// El redondeo hace falta porque no todos los valores los escribe una
  /// persona: el progreso sale de una división y arrastra todos sus
  /// decimales.
  static String textoKm(double km) {
    final redondeado = double.parse(km.toStringAsFixed(2));
    final entero = redondeado.toInt();
    return redondeado == entero ? '$entero' : '$redondeado';
  }
}

/// Cuánto le queda al reto, contado en días enteros.
///
/// Se dice en días y no con fechas porque es lo que el corredor necesita
/// decidir: "termina hoy" mueve a salir a correr, "del 21 al 27 de
/// septiembre" hay que traducirlo mentalmente.
class _Vigencia extends StatelessWidget {
  const _Vigencia({required this.reto, required this.hoy});

  final Reto reto;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    final quedan = reto.vigencia.diasRestantesDesde(hoy);

    final (texto, fondo, color) = switch (quedan) {
      0 => ('Terminado', AppColors.bgAlt, AppColors.ink3),
      // El último día se avisa en rojo: es ahora o nunca.
      1 => ('Termina hoy', AppColors.dangerTint, AppColors.danger),
      2 => ('Queda 1 día', AppColors.accentTint, AppColors.accentInk),
      _ => ('Quedan ${quedan - 1} días', AppColors.bgAlt, AppColors.ink2),
    };

    return InsigniaReto(texto: texto, fondo: fondo, color: color);
  }
}

/// Icono cuadrado con el color de cada periodicidad.
class IconoPeriodicidad extends StatelessWidget {
  const IconoPeriodicidad({required this.periodicidad, super.key});

  final PeriodicidadReto periodicidad;

  @override
  Widget build(BuildContext context) {
    final (icono, fondo, color) = switch (periodicidad) {
      PeriodicidadReto.diaria => (
        Icons.schedule,
        AppColors.accentTint,
        AppColors.accentInk,
      ),
      PeriodicidadReto.semanal => (
        Icons.bolt_outlined,
        AppColors.primaryTint,
        AppColors.primaryDark,
      ),
      PeriodicidadReto.mensual => (
        Icons.calendar_month_outlined,
        AppColors.secondaryTint,
        AppColors.secondaryDark,
      ),
    };

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icono, size: 22, color: color),
    );
  }
}

/// Etiqueta redondeada del prototipo (`.badge`).
/// El aviso de por qué un reto no se puede activar todavía.
///
/// Se dice en la tarjeta y no al pulsar: enterarse después de haber decidido
/// es lo que molesta.
class _Bloqueo extends StatelessWidget {
  const _Bloqueo({required this.motivo});

  final String motivo;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 14, color: AppColors.ink3),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            motivo,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.ink3,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class InsigniaReto extends StatelessWidget {
  const InsigniaReto({
    required this.texto,
    this.fondo = AppColors.bgAlt,
    this.color = AppColors.ink2,
    super.key,
  });

  final String texto;
  final Color fondo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
