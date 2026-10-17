import 'package:flutter/material.dart';

import '../models/ruta.dart';
import '../theme/app_colors.dart';
import '../utils/fecha_relativa.dart';
import 'tarjeta_reto.dart' show TarjetaReto;
import 'traza_card.dart';

/// Una ruta publicada en un listado: su nombre, quién la publicó y cuándo, y
/// cuánto mide.
///
/// El autor y la fecha son el criterio 4 de SCRUM-241: quien la consulta
/// tiene que saber de quién es lo que va a correr. La distancia es lo que
/// pide SCRUM-240 en el listado.
class TarjetaRuta extends StatelessWidget {
  const TarjetaRuta({
    required this.ruta,
    required this.ahora,
    this.onTap,
    super.key,
  });

  final Ruta ruta;

  /// El mismo instante para todas las tarjetas, para que dos rutas del mismo
  /// día no digan "Hoy" y "Ayer" al cruzar la medianoche.
  final DateTime ahora;

  final VoidCallback? onTap;

  static Key claveDe(String id) => Key('ruta-$id');

  /// Lo que se le dice a quien consulta una ruta sin distancia registrada
  /// (criterio 4 de SCRUM-240).
  static const sinDistancia = 'Distancia no disponible';

  @override
  Widget build(BuildContext context) {
    final publicada = ruta.fechaPublicacion ?? ruta.fechaCreacion;

    return TrazaCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.secondaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.route_outlined,
              size: 20,
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruta.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Por ${ruta.autorNombre} · ${fechaRelativa(publicada, ahora)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.straighten_rounded,
                      size: 14,
                      color: AppColors.ink3,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        // Los km se escriben igual en toda la app, con el
                        // mismo formato que los retos.
                        ruta.tieneDistancia
                            ? '${TarjetaReto.textoKm(ruta.distanciaKm!)} km'
                            : sinDistancia,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: ruta.tieneDistancia
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: ruta.tieneDistancia
                              ? AppColors.ink
                              : AppColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
