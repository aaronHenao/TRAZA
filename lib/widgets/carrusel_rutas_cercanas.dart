import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/ruta.dart';
import '../screens/rutas/detalle_ruta_screen.dart';
import '../screens/rutas/rutas_screen.dart';
import '../services/inicio_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'tarjeta_reto.dart' show InsigniaReto, TarjetaReto;
import 'tarjeta_ruta.dart';
import 'traza_card.dart';

/// Las rutas cercanas en la portada (SCRUM-289, criterio 4 de SCRUM-283).
///
/// Se recorren de lado, con su dificultad y su distancia, y "Ver todas" lleva
/// a la sección de Rutas. Tocar una abre su detalle (SCRUM-240), de donde se
/// vuelve a la portada.
///
/// Dos cosas las traen historias que todavía no existen, y están marcadas en
/// `docs/deudas.md`:
///
/// - **La cercanía.** Hoy son las últimas publicadas; ordenarlas por distancia
///   al usuario es HU-29, y el orden se arregla en `rutasCercanasProvider` sin
///   tocar esta tarjeta.
/// - **La dificultad.** `rutas` no tiene esa columna: la asigna HU-34 y la
///   revisa HU-35. Hasta entonces la pastilla dice [sinDificultad], que es la
///   verdad de hoy: ninguna ruta está clasificada.
class CarruselRutasCercanas extends ConsumerWidget {
  const CarruselRutasCercanas({super.key});

  static const clave = Key('inicio-rutas-cercanas');
  static const claveVerTodas = Key('inicio-rutas-ver-todas');

  /// Lo que dice la pastilla mientras nadie clasifica las rutas (HU-34).
  static const sinDificultad = 'Sin clasificar';

  /// Alto del carrusel. Fijo porque una lista horizontal no puede medir a sus
  /// hijos a lo alto.
  static const alto = 124.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutas = ref.watch(rutasCercanasProvider);
    final hayRutas = rutas.valueOrNull?.isNotEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'RUTAS CERCANAS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.52,
                  color: AppColors.ink2,
                ),
              ),
            ),
            // Sin rutas no hay nada que ver: el acceso aparece cuando sirve,
            // como el del historial.
            if (hayRutas)
              GestureDetector(
                key: claveVerTodas,
                // `go`: Rutas es una sección de la barra inferior.
                onTap: () => context.go(RutasScreen.ruta),
                child: const Text(
                  'Ver todas',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        switch (rutas) {
          AsyncData(value: final lista) when lista.isEmpty => const _Aviso(
            'Todavía no hay rutas publicadas. Cuando la comunidad publique '
            'alguna, la verás aquí.',
          ),
          AsyncData(value: final lista) => _Carrusel(rutas: lista),
          AsyncError() => const _Aviso(
            'No pudimos cargar las rutas. Desliza hacia abajo para volver a '
            'intentarlo.',
          ),
          _ => const _Aviso('Cargando las rutas cercanas…'),
        },
      ],
    );
  }
}

class _Carrusel extends StatelessWidget {
  const _Carrusel({required this.rutas});

  final List<Ruta> rutas;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: CarruselRutasCercanas.clave,
      height: CarruselRutasCercanas.alto,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // El carrusel va de borde a borde de la tarjeta, sin huecos a los
        // lados: el padding lo pone la portada.
        padding: EdgeInsets.zero,
        itemCount: rutas.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => _TarjetaCorta(ruta: rutas[i]),
      ),
    );
  }
}

/// Una ruta en el carrusel: su nombre, su dificultad y su distancia.
///
/// Es más angosta que la tarjeta de los listados ([TarjetaRuta]) porque aquí
/// caben varias de lado; a cambio deja fuera el autor y la fecha, que se leen
/// en el detalle.
class _TarjetaCorta extends StatelessWidget {
  const _TarjetaCorta({required this.ruta});

  final Ruta ruta;

  /// Ancho de cada tarjeta. Deja asomar la siguiente en la pantalla más
  /// estrecha, que es lo que invita a arrastrar.
  static const ancho = 186.0;

  static Key claveDe(String rutaId) => Key('inicio-ruta-$rutaId');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      child: TrazaCard(
        key: claveDe(ruta.id),
        padding: const EdgeInsets.all(AppSpacing.md),
        // `push`: al cerrar el detalle se vuelve a la portada.
        onTap: () => context.push(DetalleRutaScreen.rutaDe(ruta.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                ruta.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const InsigniaReto(texto: CarruselRutasCercanas.sinDificultad),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.linear_scale_rounded,
                  size: 14,
                  color: AppColors.ink3,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    // Los km se escriben igual en toda la app.
                    ruta.tieneDistancia
                        ? '${TarjetaReto.textoKm(ruta.distanciaKm!)} km'
                        // La misma frase del listado y del detalle
                        // (criterio 4 de SCRUM-240).
                        : TarjetaRuta.sinDistancia,
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
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 12.5,
          color: AppColors.ink2,
          height: 1.4,
        ),
      ),
    );
  }
}
