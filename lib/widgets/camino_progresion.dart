import 'package:flutter/material.dart';

import '../models/mapa_progresion.dart';
import '../models/ruta.dart';
import '../theme/app_colors.dart';
import 'tarjeta_ruta_explorar.dart';

/// El camino del mapa de progresión: las rutas oficiales de arriba abajo,
/// con el marcador "Tú" en la que le toca al corredor (rutas oficiales,
/// etapa 2).
///
/// Es una columna y no un `ListView`: el desplazamiento lo pone la pantalla,
/// y así todas las paradas existen aunque queden fuera de la vista.
class CaminoProgresion extends StatelessWidget {
  const CaminoProgresion({required this.mapa, this.onTapRuta, super.key});

  final MapaProgresion mapa;

  /// Qué hacer al tocar una parada, sea cual sea su estado: el detalle de la
  /// ruta sirve también para ver la que viene.
  final void Function(Ruta ruta)? onTapRuta;

  static const claveMarcador = Key('camino-marcador');
  static Key claveParada(String rutaId) => Key('parada-$rutaId');

  /// Ancho de la columna donde van los círculos y la línea del camino.
  static const _anchoRiel = 40.0;

  @override
  Widget build(BuildContext context) {
    final paradas = mapa.paradas;
    final ultima = paradas.length - 1;
    final actual = mapa.indiceActual;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paradas.length; i++) ...[
          _Parada(
            key: claveParada(paradas[i].ruta.id),
            parada: paradas[i],
            conMarcador: i == actual,
            onTap: onTapRuta == null ? null : () => onTapRuta!(paradas[i].ruta),
          ),
          if (i < ultima)
            // Relleno hasta donde va el corredor: los tramos que quedan
            // atrás de su parada.
            _Tramo(recorrido: actual != null && i < actual),
        ],
      ],
    );
  }
}

class _Parada extends StatelessWidget {
  const _Parada({
    required this.parada,
    required this.conMarcador,
    required this.onTap,
    super.key,
  });

  final ParadaMapa parada;
  final bool conMarcador;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ruta = parada.ruta;
    final (icono, etiqueta, activa) = switch (parada.estado) {
      EstadoParada.completada => (Icons.check_circle, 'Completada', true),
      // Bandera y no corredor: el corredor es el marcador "Tú", que va justo
      // en esta parada.
      EstadoParada.siguiente => (Icons.flag_outlined, 'Siguiente', true),
      EstadoParada.bloqueada => (Icons.lock_outline, 'Bloqueada', false),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: CaminoProgresion._anchoRiel,
              height: CaminoProgresion._anchoRiel,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activa ? AppColors.primaryTint : AppColors.bgAlt,
              ),
              child: Icon(
                icono,
                size: 20,
                color: activa ? AppColors.primary : AppColors.ink3,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ruta.nombre,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: activa ? AppColors.ink : AppColors.ink2,
                    ),
                  ),
                  Text(
                    TarjetaRutaExplorar.distanciaYDificultad(ruta),
                    style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                  ),
                  Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: activa ? AppColors.primary : AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            if (conMarcador) ...[const SizedBox(width: 8), const _Marcador()],
          ],
        ),
      ),
    );
  }
}

/// La línea entre dos paradas: llena si ya quedó atrás.
class _Tramo extends StatelessWidget {
  const _Tramo({required this.recorrido});

  final bool recorrido;

  static const _alto = 28.0;

  @override
  Widget build(BuildContext context) {
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
                  color: recorrido ? AppColors.primary : AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Tú": dónde está el corredor. Usa un icono distinto de los de las paradas
/// para no confundirse con ellas.
class _Marcador extends StatelessWidget {
  const _Marcador();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: CaminoProgresion.claveMarcador,
      height: 28,
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
