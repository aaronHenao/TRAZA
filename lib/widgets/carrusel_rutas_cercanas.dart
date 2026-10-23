import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/estado_permisos.dart';
import '../models/ruta.dart';
import '../screens/rutas/detalle_ruta_screen.dart';
import '../screens/rutas/rutas_screen.dart';
import '../services/inicio_provider.dart';
import '../services/permisos_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'tarjeta_ruta_explorar.dart';
import 'traza_card.dart';

/// Las rutas cercanas en la portada (SCRUM-289, criterio 4 de SCRUM-283).
///
/// Se recorren de lado y "Ver todas" lleva a la sección de Rutas. Tocar una
/// abre su detalle (SCRUM-240), de donde se vuelve a la portada.
///
/// Cada ruta va en la tarjeta compacta de Explorar rutas
/// ([TarjetaRutaExplorar.compacta], SCRUM-247): miniatura, nombre,
/// dificultad, distancia, desnivel y quién la creó, igual que en la lista.
///
/// La cercanía todavía no ordena el carrusel: hoy son las últimas
/// publicadas. Está anotado en `docs/deudas.md`, y se arregla en
/// `rutasCercanasProvider` sin tocar este widget.
class CarruselRutasCercanas extends ConsumerWidget {
  const CarruselRutasCercanas({super.key});

  static const clave = Key('inicio-rutas-cercanas');
  static const claveVerTodas = Key('inicio-rutas-ver-todas');
  static const claveSinPermiso = Key('inicio-rutas-sin-permiso');
  static const claveAceptarUbicacion = Key('inicio-rutas-aceptar-ubicacion');

  /// Por qué se pide la ubicación aquí (SCRUM-290). Lo mismo que pedirá la
  /// sección de Rutas: sin ella no se puede saber qué está cerca.
  static const porQueLaUbicacion =
      'Concede el permiso de ubicación para ver las rutas que tienes cerca.';

  /// Alto del carrusel con el texto del sistema a su tamaño: el de la
  /// tarjeta compacta. Es fijo porque una lista horizontal no puede medir a
  /// sus hijos a lo alto.
  static const alto = TarjetaRutaExplorar.altoCompacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = ref.watch(permisosProvider);
    final rutas = ref.watch(rutasCercanasProvider);
    final hayUbicacion = permisos.ubicacion == EstadoPermiso.concedido;
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
            // Sin rutas que mirar, o sin permiso para saber cuáles están
            // cerca, el acceso no aparece: primero hay algo que resolver aquí.
            if (hayRutas && hayUbicacion)
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
        // El permiso se resuelve antes que las rutas: sin él, la lista no
        // puede decir qué está cerca, así que ni se muestra ni se consulta en
        // balde (criterio 4 de SCRUM-283 y criterio 3 de HU-29).
        if (!permisos.consultado)
          const _Aviso('Cargando las rutas cercanas…')
        else if (!hayUbicacion)
          _SinPermiso(
            bloqueado: permisos.ubicacion == EstadoPermiso.bloqueado,
            solicitando: permisos.solicitandoUbicacion,
          )
        else
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

/// Sin permiso de ubicación: se explica para qué hace falta y se ofrece
/// concederlo, en vez de dejar el hueco o mostrar rutas que no se sabe si
/// están cerca.
///
/// Es la misma idea de `RequierePermisoUbicacion`, pero dentro de la portada:
/// aquí no se bloquea la pantalla, solo este bloque.
class _SinPermiso extends ConsumerWidget {
  const _SinPermiso({required this.bloqueado, required this.solicitando});

  /// El usuario lo negó para siempre: el sistema ya no muestra su ventana y lo
  /// único que queda es ir a los ajustes del teléfono.
  final bool bloqueado;

  final bool solicitando;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = ref.read(permisosProvider.notifier);

    return TrazaCard(
      key: CarruselRutasCercanas.claveSinPermiso,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.secondaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_off_outlined,
                  size: 20,
                  color: AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  bloqueado
                      ? 'Activa la ubicación en los ajustes del teléfono para '
                            'ver las rutas que tienes cerca.'
                      : CarruselRutasCercanas.porQueLaUbicacion,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink2,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: CarruselRutasCercanas.claveAceptarUbicacion,
            onPressed: solicitando
                ? null
                : () => bloqueado
                      ? permisos.abrirAjustes()
                      : permisos.solicitarUbicacion(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }
}

class _Carrusel extends StatelessWidget {
  const _Carrusel({required this.rutas});

  final List<Ruta> rutas;

  @override
  Widget build(BuildContext context) {
    // El alto es fijo —una lista horizontal no mide a lo alto—, así que con el
    // texto del sistema en grande crece con él: si no, el nombre en dos
    // líneas, la pastilla y la distancia no caben y algo se pierde. Acotado,
    // porque pasado de ahí el carrusel se comería la pantalla.
    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    return SizedBox(
      key: CarruselRutasCercanas.clave,
      height: CarruselRutasCercanas.alto * escala,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // El carrusel va de borde a borde de la tarjeta, sin huecos a los
        // lados: el padding lo pone la portada.
        padding: EdgeInsets.zero,
        itemCount: rutas.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => TarjetaRutaExplorar.compacta(
          key: TarjetaRutaExplorar.claveDe(rutas[i].id),
          ruta: rutas[i],
          // `push`: al cerrar el detalle se vuelve a la portada.
          onTap: () => context.push(DetalleRutaScreen.rutaDe(rutas[i].id)),
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
