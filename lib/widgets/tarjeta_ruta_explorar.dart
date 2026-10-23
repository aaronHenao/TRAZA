import 'package:flutter/material.dart';

import '../models/ruta.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'miniatura_ruta.dart';
import 'tarjeta_reto.dart' show InsigniaReto, TarjetaReto;
import 'tarjeta_ruta.dart';
import 'traza_card.dart';

/// La tarjeta de una ruta en Explorar rutas y en el carrusel de la portada
/// (SCRUM-247).
///
/// Muestra lo que pide el criterio 2 de HU-29: la miniatura del recorrido,
/// el nombre, la dificultad, la distancia, el desnivel y quién la creó. Es
/// la misma en los dos sitios para que una ruta se reconozca igual en la
/// portada que en la lista. Lo que cambia es la disposición: en la lista va
/// de lado ([TarjetaRutaExplorar.new]) y en el carrusel, que es angosto,
/// hacia abajo ([TarjetaRutaExplorar.compacta]).
///
/// Dos datos todavía no existen y se dice así, como acordó el equipo hasta
/// que llegue HU-34: la dificultad, que asigna esa historia, y el desnivel,
/// que necesita una altitud que el GPS de la app no guarda.
class TarjetaRutaExplorar extends StatelessWidget {
  /// De lado, para la lista de Explorar rutas.
  const TarjetaRutaExplorar({required this.ruta, this.onTap, super.key})
    : compacta = false;

  /// Hacia abajo y de ancho fijo, para el carrusel de la portada.
  const TarjetaRutaExplorar.compacta({
    required this.ruta,
    this.onTap,
    super.key,
  }) : compacta = true;

  final Ruta ruta;

  /// Abre el detalle. Sin esto la tarjeta no se puede tocar.
  final VoidCallback? onTap;

  final bool compacta;

  /// Lo que dice la pastilla mientras nadie clasifica las rutas (HU-34).
  static const sinDificultad = 'Sin clasificar';

  /// Lo que se dice del desnivel mientras no haya de dónde sacarlo.
  static const sinDesnivel = 'Desnivel no disponible';

  /// Ancho de la tarjeta compacta. Deja asomar la siguiente en la pantalla
  /// más estrecha, que es lo que invita a arrastrar el carrusel.
  static const anchoCompacta = 186.0;

  /// Alto de la tarjeta compacta con el texto del sistema a su tamaño. Con
  /// el texto más grande crece quien la contiene: un carrusel no puede medir
  /// a sus tarjetas a lo alto.
  static const altoCompacta = 240.0;

  /// Lado de la miniatura en la tarjeta de la lista.
  static const ladoMiniatura = 76.0;

  /// Alto de la miniatura en la tarjeta compacta: ocupa todo el ancho.
  static const altoMiniaturaCompacta = 64.0;

  static Key claveDe(String rutaId) => Key('tarjeta-ruta-$rutaId');

  @override
  Widget build(BuildContext context) {
    return compacta ? _compacta() : _deLado();
  }

  Widget _deLado() {
    return TrazaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: ladoMiniatura,
            child: MiniaturaRuta(puntos: ruta.miniatura),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Nombre(ruta: ruta, lineas: 2),
                const SizedBox(height: 2),
                _Creador(ruta: ruta),
                const SizedBox(height: AppSpacing.sm),
                // Saltan de línea cuando no caben, en vez de cortarse.
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const _Dificultad(),
                    _Distancia(ruta: ruta),
                    const _Desnivel(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compacta() {
    return SizedBox(
      width: anchoCompacta,
      child: TrazaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: altoMiniaturaCompacta,
              width: double.infinity,
              child: MiniaturaRuta(puntos: ruta.miniatura),
            ),
            const SizedBox(height: 10),
            // Una sola línea: en el carrusel las tarjetas tienen que medir
            // lo mismo, y el nombre completo está en la lista y el detalle.
            _Nombre(ruta: ruta, lineas: 1),
            const SizedBox(height: 2),
            _Creador(ruta: ruta),
            const SizedBox(height: AppSpacing.sm),
            const _Dificultad(),
            const SizedBox(height: AppSpacing.sm),
            _Distancia(ruta: ruta),
            const SizedBox(height: AppSpacing.xs),
            const _Desnivel(),
          ],
        ),
      ),
    );
  }
}

class _Nombre extends StatelessWidget {
  const _Nombre({required this.ruta, required this.lineas});

  final Ruta ruta;
  final int lineas;

  @override
  Widget build(BuildContext context) {
    return Text(
      ruta.nombre,
      maxLines: lineas,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}

/// Quién la creó (criterio 2 de HU-29).
class _Creador extends StatelessWidget {
  const _Creador({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Por ${ruta.autorNombre}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.ink2),
    );
  }
}

/// La dificultad. Hasta HU-34 ninguna ruta la tiene, y la pastilla lo dice
/// en vez de inventarse una.
class _Dificultad extends StatelessWidget {
  const _Dificultad();

  @override
  Widget build(BuildContext context) {
    return const InsigniaReto(texto: TarjetaRutaExplorar.sinDificultad);
  }
}

class _Distancia extends StatelessWidget {
  const _Distancia({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context) {
    final tiene = ruta.tieneDistancia;

    return _Dato(
      icono: Icons.linear_scale_rounded,
      // Los km se escriben igual en toda la app, y la falta de distancia se
      // dice con la frase del listado y del detalle (criterio 4 de
      // SCRUM-240).
      texto: tiene
          ? '${TarjetaReto.textoKm(ruta.distanciaKm!)} km'
          : TarjetaRuta.sinDistancia,
      destacado: tiene,
    );
  }
}

class _Desnivel extends StatelessWidget {
  const _Desnivel();

  @override
  Widget build(BuildContext context) {
    return const _Dato(
      icono: Icons.terrain_outlined,
      texto: TarjetaRutaExplorar.sinDesnivel,
      destacado: false,
    );
  }
}

/// Un dato con su icono. Lo que se sabe va destacado; lo que falta, en gris.
class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.texto,
    required this.destacado,
  });

  final IconData icono;
  final String texto;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: AppColors.ink3),
        const SizedBox(width: 5),
        // Flexible: con el texto del sistema grande, en la tarjeta compacta
        // el dato se corta con puntos suspensivos en vez de desbordarla.
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
              color: destacado ? AppColors.ink : AppColors.ink3,
            ),
          ),
        ),
      ],
    );
  }
}
