import 'package:flutter/material.dart';

import '../models/mapa_progresion.dart';
import '../theme/app_colors.dart';

/// El camino del mapa de progresión (SCRUM-226): el inicio y los niveles de
/// arriba abajo, con el marcador "Tú" donde va el corredor.
///
/// Es una columna y no un `ListView`: el desplazamiento lo pone la pantalla,
/// y así todas las paradas existen aunque queden fuera de la vista.
class CaminoProgresion extends StatelessWidget {
  const CaminoProgresion({required this.mapa, super.key});

  final MapaProgresion mapa;

  static const claveMarcador = Key('camino-marcador');

  /// Ancho de la columna donde van los círculos y la línea del camino.
  static const _anchoRiel = 40.0;

  @override
  Widget build(BuildContext context) {
    final paradas = mapa.paradas;
    final ultima = paradas.length - 1;
    final indice = mapa.indiceActual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paradas.length; i++) ...[
          _Parada(
            key: ValueKey('parada-$i'),
            parada: paradas[i],
            // Sin tramo por delante (nivel máximo o sin niveles), el
            // marcador se queda sobre la parada.
            conMarcador: i == indice && mapa.enUltimaParada,
          ),
          if (i < ultima)
            _Tramo(
              key: ValueKey('tramo-$i'),
              recorrido: i < indice
                  ? 1
                  : (i == indice ? mapa.avanceEnTramo : 0),
              conMarcador: i == indice,
            ),
        ],
      ],
    );
  }
}

class _Parada extends StatelessWidget {
  const _Parada({required this.parada, required this.conMarcador, super.key});

  final ParadaMapa parada;
  final bool conMarcador;

  @override
  Widget build(BuildContext context) {
    final alcanzada = parada.alcanzada;
    final icono = parada.esInicio
        ? Icons.flag
        : (alcanzada ? Icons.check_circle : Icons.lock_outline);

    return Row(
      children: [
        Container(
          width: CaminoProgresion._anchoRiel,
          height: CaminoProgresion._anchoRiel,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: alcanzada ? AppColors.primaryTint : AppColors.bgAlt,
          ),
          child: Icon(
            icono,
            size: 20,
            color: alcanzada ? AppColors.primary : AppColors.ink3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parada.nombre,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: alcanzada ? AppColors.ink : AppColors.ink2,
                ),
              ),
              if (!parada.esInicio)
                Text(
                  '${parada.umbralExperiencia} XP',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
            ],
          ),
        ),
        if (conMarcador) ...[const SizedBox(width: 8), const _Marcador()],
      ],
    );
  }
}

/// La línea entre dos paradas, rellena hasta donde va el corredor.
class _Tramo extends StatelessWidget {
  const _Tramo({required this.recorrido, required this.conMarcador, super.key});

  /// De 0 a 1. Null no ocurre aquí (siempre hay siguiente parada), pero se
  /// trata como cero.
  final double? recorrido;
  final bool conMarcador;

  static const _alto = 72.0;
  static const _altoMarcador = 28.0;

  @override
  Widget build(BuildContext context) {
    final fraccion = recorrido ?? 0;

    return SizedBox(
      height: _alto,
      child: Row(
        children: [
          SizedBox(
            width: CaminoProgresion._anchoRiel,
            child: Center(
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: fraccion,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: conMarcador
                ? Stack(
                    children: [
                      Positioned(
                        top: fraccion * (_alto - _altoMarcador),
                        left: 0,
                        child: const _Marcador(),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// "Tú": dónde está el corredor (criterio 1). Usa un icono distinto de los de
/// las paradas para no confundirse con ellas.
class _Marcador extends StatelessWidget {
  const _Marcador();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: CaminoProgresion.claveMarcador,
      height: _Tramo._altoMarcador,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_run, size: 16, color: AppColors.accentInk),
          SizedBox(width: 4),
          Text(
            'Tú',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.accentInk,
            ),
          ),
        ],
      ),
    );
  }
}
