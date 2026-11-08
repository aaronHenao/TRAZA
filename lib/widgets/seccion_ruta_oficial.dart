import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verificacion_ruta.dart';
import '../services/mapa_progresion_provider.dart';
import '../services/rutas_oficiales_provider.dart';
import '../services/rutas_oficiales_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// En el resumen de una ruta oficial: si se completó (rutas oficiales,
/// etapa 4).
///
/// Lo decide la base al comparar los puntos GPS con el trazado; aquí solo se
/// pregunta y se muestra. Si se completó, el mapa de progresión se vuelve a
/// consultar para que avance.
class SeccionRutaOficial extends ConsumerWidget {
  const SeccionRutaOficial({
    required this.entrenamientoId,
    required this.nombreRuta,
    super.key,
  });

  final String entrenamientoId;
  final String nombreRuta;

  static const clave = Key('seccion-ruta-oficial');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proveedor = verificacionRutaProvider(entrenamientoId);

    // Una sola vez, cuando llega la respuesta: no en cada dibujo.
    ref.listen(proveedor, (_, siguiente) {
      if (siguiente.valueOrNull?.completada ?? false) {
        ref.invalidate(mapaProgresionProvider);
      }
    });

    final contenido = ref
        .watch(proveedor)
        .when<Widget?>(
          skipLoadingOnRefresh: false,
          loading: () => const _Aviso('Comprobando si completaste la ruta…'),
          error: (error, _) => switch (error) {
            RecorridoNoValidoException() => const _Aviso(
              'No pudimos validar este recorrido',
            ),
            RutaNoOficialException() => const _Aviso(
              'Esta ruta ya no es parte del mapa',
            ),
            _ => _Aviso(
              'No pudimos comprobar la ruta',
              onReintentar: () => ref.invalidate(proveedor),
            ),
          },
          // Null: la base dice que el entrenamiento fue libre.
          data: (verificacion) => verificacion == null
              ? null
              : _Resultado(verificacion: verificacion, nombreRuta: nombreRuta),
        );
    if (contenido == null) return const SizedBox.shrink();

    return Container(
      key: clave,
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: contenido,
    );
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.verificacion, required this.nombreRuta});

  final VerificacionRuta verificacion;
  final String nombreRuta;

  @override
  Widget build(BuildContext context) {
    final completada = verificacion.completada;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          completada ? Icons.emoji_events_outlined : Icons.route_outlined,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                completada
                    ? '¡Completaste $nombreRuta!'
                    : 'Cubriste el ${verificacion.porcentaje} % de $nombreRuta',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                completada
                    ? 'Cubriste el ${verificacion.porcentaje} % del trazado.'
                    : 'Necesitas el ${verificacion.porcentajeNecesario} % '
                          'para completarla.',
                style: const TextStyle(fontSize: 13, color: AppColors.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto, {this.onReintentar});

  final String texto;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
        ),
        if (onReintentar case final reintentar?)
          TextButton(onPressed: reintentar, child: const Text('Reintentar')),
      ],
    );
  }
}
